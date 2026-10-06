# Protocol-free publish/subscribe core.
#
# This module owns the generic fan-out engine: a broker holding per-subscriber
# bounded `Channel`s, non-blocking delivery under one lock, drop policies,
# optional in-process callbacks, and opportunistic pruning of dead subscribers.
# Protocol adapters (MCP subscriptions) layer their event model on top by
# choosing the broker's element type and filtering in the subscriber predicate.
#
# Lock ordering (the invariant every caller must respect): `broker.lock` may be
# held while doing channel ops on subscriber queues; never take a consumer or
# transport lock while holding `broker.lock`. Delivery happens under the lock,
# which makes ordering (e.g. ack-before-broadcast, close-last) a lock invariant
# rather than a race to reason about. Matcher predicates also run under the lock,
# so they must be quick and side-effect free: they must not block, take other
# locks, or call back into the broker (`publish!`/`subscribe!`/`unsubscribe!`).
# Re-entrant work belongs in a `callback`, which runs after the lock is released.

module PubSub

using Base.Threads: ReentrantLock, Atomic, atomic_add!

export Broker, Subscription, subscribe!, unsubscribe!, publish!, subscribers, drops, close_all!

# Delivery policies applied when a subscriber's bounded queue is full:
# - `:drop_newest`: discard the incoming value and count a drop;
# - `:drop_oldest`: discard the oldest queued value to make room;
# - `:disconnect`: close the queue (buffered values stay drainable) and prune.
const POLICIES = (:drop_newest, :drop_oldest, :disconnect)

# `publish!` runs a full dead-record sweep every this many publishes, so records
# that died on topics nobody publishes to cannot stay pinned until the next
# capacity-pressure registration. The sweep is atomic-only (see `sweep_broker!`),
# so it adds no channel locks to the publish path.
const SWEEP_INTERVAL = 64

# The match test of a subscription. Concrete matcher types keep the per-publish
# call out of megamorphic `Function`-field dispatch: the field is typed as a
# small union, so `matches` union-splits instead of dispatching dynamically.
abstract type Matcher end

struct TopicMatcher <: Matcher
    key :: String
end

struct RegexMatcher <: Matcher
    pattern :: Regex
end

struct PredicateMatcher <: Matcher
    predicate :: Function
end

const SubscriptionMatcher = Union{TopicMatcher,RegexMatcher,PredicateMatcher}

matches(matcher::TopicMatcher, topic::String, _value)::Bool = topic == matcher.key
matches(matcher::RegexMatcher, topic::String, _value)::Bool = occursin(matcher.pattern, topic)
matches(matcher::PredicateMatcher, _topic::String, value)::Bool = matcher.predicate(value) === true

"""
    CapacityError(cap)

Raised by `subscribe!` when the broker already holds `cap` active
subscriptions. The caller must unsubscribe (or let a dead subscriber be pruned,
which `subscribe!` does first) before retrying.
"""
struct CapacityError <: Exception
    cap :: Int
end

Base.showerror(io::IO, error::CapacityError) =
    print(io, "subscription limit reached ($(error.cap))")

"""
    Subscription{T}

One subscriber's view of the broker: a bounded queue carrying values of type
`T`, an optional in-process callback, and lifecycle flags.

# Fields
- `id::String`: broker-unique id, for logs/introspection
- `label::String`: human-readable label (the topic, or the given label)
- `topic::Union{Nothing,String}`: exact topic for fast-path subscriptions
- `matcher::SubscriptionMatcher`: the topic/pattern/predicate test
- `queue::Channel{T}`: the bounded delivery queue (a pre-created channel may be
  supplied so an acknowledgement can be written into it before registration)
- `callback::Union{Nothing,Function}`: `(topic, value) -> nothing`, an observer
  invoked on the publisher's task after the lock is released; it sees every
  matching value even when the queue dropped or disconnected it
- `policy::Symbol`: `:drop_newest` | `:drop_oldest` | `:disconnect`
- `drops::Threads.Atomic{Int}`: values lost to queue pressure: `:drop_newest`
  discards, `:drop_oldest` values displaced to make room, plus an incoming
  `:drop_oldest` value that still could not be enqueued
- `active::Threads.Atomic{Bool}`: cleared when the subscription ends
"""
mutable struct Subscription{T}
    id       :: String
    label    :: String
    topic    :: Union{Nothing,String}
    matcher  :: SubscriptionMatcher
    queue    :: Channel{T}
    callback :: Union{Nothing,Function}
    policy   :: Symbol
    drops    :: Atomic{Int}
    active   :: Atomic{Bool}
end

# Hot-path liveness. Every sanctioned end-of-life path (`Base.close(sub)`,
# `unsubscribe!`, the `:disconnect` policy, `close_all!`, and MCP teardown)
# clears this atomic before closing the queue, so the flag alone is race-free.
isdead(sub::Subscription)::Bool = !sub.active[]

# Cold-path liveness: also observes a queue closed behind the broker's back
# (a transport may close `sub.queue` directly). The state read is taken under
# the channel lock so it cannot race with `close`.
function queue_closed(sub::Subscription)::Bool
    lock(sub.queue)
    try
        return !isopen(sub.queue)
    finally
        unlock(sub.queue)
    end
end

expired(sub::Subscription)::Bool = isdead(sub) || queue_closed(sub)

Base.isopen(sub::Subscription)::Bool = !expired(sub)

function Base.close(sub::Subscription)
    sub.active[] = false
    close(sub.queue)
    return nothing
end

"""
    drops(sub::Subscription) -> Int

How many published values this subscription lost to queue pressure:
`:drop_newest` discards, `:drop_oldest` values displaced to make room, plus an
incoming `:drop_oldest` value that still could not be enqueued (an unbuffered
or already-closed queue). `:disconnect` closes without counting.
"""
drops(sub::Subscription)::Int = sub.drops[]

"""
    Broker{T}(; cap=256)

The publish/subscribe broker. `T` is the value type delivered to subscribers;
`cap` bounds the number of active subscriptions.

Exact-topic subscriptions live in `exact` (a dictionary fast path);
regex/predicate subscriptions live in `patterns` and are scanned on publish.
All registry state is guarded by `lock`. `count` tracks how many subscription
records are stored (including dead ones not yet pruned), so the capacity check
does not have to recount them. `publishes` counts publishes since the last full
dead-record sweep; every `SWEEP_INTERVAL` publishes the broker sweeps dead
records globally so deaths on quiet topics cannot stay pinned until the next
capacity-pressure registration. `id_counter` hands out broker-unique
subscription ids.
"""
mutable struct Broker{T}
    lock       :: ReentrantLock
    exact      :: Dict{String,Vector{Subscription{T}}}
    patterns   :: Vector{Subscription{T}}
    cap        :: Int
    count      :: Int
    publishes  :: Int
    id_counter :: Atomic{UInt64}
end

function Broker{T}(; cap::Integer=256) where {T}
    if cap < 0
        throw(ArgumentError("broker capacity must be non-negative"))
    end
    return Broker{T}(
        ReentrantLock(), 
        Dict{String,Vector{Subscription{T}}}(),    
        Subscription{T}[], 
        Int(cap), 
        0, 
        0, 
        Atomic{UInt64}(0)
    )
end

Broker(; kwargs...) = Broker{Any}(; kwargs...)

# Broker-unique ids for introspection/logging. Only uniqueness within the broker
# is needed (the id is not a wire identifier), so the counter lives on the broker
# instead of in module-global state.
next_id(broker::Broker) = "sub-" * string(atomic_add!(broker.id_counter, UInt64(1)))

# Shared registry sweep: `dead(sub)` selects the records to drop and must not
# block. Callers must hold `broker.lock`.
function sweep_records!(broker::Broker, dead::F) where {F}
    removed = 0
    if !isempty(broker.exact)
        empties = String[]
        for (topic, subs) in broker.exact
            before = length(subs)
            filter!(sub -> !dead(sub), subs)
            removed += before - length(subs)
            if isempty(subs)
                push!(empties, topic)
            end
        end
        for topic in empties
            delete!(broker.exact, topic)
        end
    end
    if !isempty(broker.patterns)
        before = length(broker.patterns)
        filter!(sub -> !dead(sub), broker.patterns)
        removed += before - length(broker.patterns)
    end
    broker.count -= removed
    return removed
end

# Drop dead records. Callers must hold `broker.lock`. Uses the race-free
# `expired` check because a dead record may be a subscription whose queue was
# closed directly; the publish path instead uses the atomic `isdead` only.
function prune!(broker::Broker)
    sweep_records!(broker, expired)
    return broker
end

# The amortized publish-path sweep: atomic-only, so it takes no subscriber
# channel locks while holding `broker.lock`.
function sweep_broker!(broker::Broker)
    sweep_records!(broker, isdead)
    return broker
end

# Hot-path record cleanup for `publish!`: atomic-only so the delivery path
# takes no channel locks while holding `broker.lock`. Returns the removed count.
function sweep_dead!(subs::Vector{<:Subscription})::Int
    before = length(subs)
    filter!(sub -> !isdead(sub), subs)
    return before - length(subs)
end

# Non-blocking buffered put: check the buffered count under the channel's own
# lock, then `put!` under that same lock so it can never block. Holding the
# channel lock is what makes it race-free: producers need that lock and
# consumers only remove items, so a not-full channel stays not-full through the
# push. Unbuffered channels are refused (a `put!` would wait for a taker).
function try_put!(channel::Channel{T}, value::T) where {T}
    if !Base.isbuffered(channel)
        return false
    end
    lock(channel)
    try
        if !isopen(channel)
            return false
        end
        if queue_full(channel)
            return false
        end
        put!(channel, value)
        return true
    finally
        unlock(channel)
    end
end

# `Base.isfull` only exists on Julia >= 1.12; older versions need the capacity
# check expressed against the stable `data`/`sz_max` fields.
function queue_full(channel::Channel)::Bool
    if isdefined(Base, :isfull)
        return Base.isfull(channel)
    end
    return length(channel.data) >= channel.sz_max
end

# Non-blocking buffered take: under the channel lock an `isready` check cannot
# be overtaken by another taker (they need the same lock), so `take!` returns
# immediately. Returns `(value, true)` or `(nothing, false)`.
function try_take!(channel::Channel{T})::Union{Tuple{T,Bool},Tuple{Nothing,Bool}} where {T}
    if !Base.isbuffered(channel)
        return nothing, false
    end
    lock(channel)
    try
        if !isready(channel)
            return nothing, false
        end
        return take!(channel), true
    finally
        unlock(channel)
    end
end

# Non-blocking delivery into one subscriber's queue, applying its policy.
# Returns `true` when the value was enqueued. Callers must hold `broker.lock`.
function deliver!(sub::Subscription{T}, value::T) where {T}
    if isdead(sub)
        return false
    end

    if try_put!(sub.queue, value)
        return true
    end

    if sub.policy === :drop_oldest
        # Make room by discarding the oldest queued value. The displaced value
        # is lost to pressure and counts as a drop even when the incoming value
        # takes its place; if there is nothing to take (unbuffered queue) or
        # the requeue still fails (closed queue), the incoming value is lost as
        # well and counts too.
        _, removed = try_take!(sub.queue)
        if removed
            atomic_add!(sub.drops, 1)
            if try_put!(sub.queue, value)
                return true
            end
        end
        atomic_add!(sub.drops, 1)
        return false
    elseif sub.policy === :disconnect
        # Keep already-buffered frames drainable: the consumer sees the close
        # only after emptying the queue.
        sub.active[] = false
        close(sub.queue)
        return false
    end

    atomic_add!(sub.drops, 1)
    return false
end

function make_queue(::Type{T}, channel, csize::Integer) where {T}
    if isnothing(channel)
        if csize < 0
            throw(ArgumentError("queue capacity must be non-negative"))
        end
        return Channel{T}(csize)
    end
    if !(channel isa Channel{T})
        throw(ArgumentError(
            "provided channel must be a Channel{$T}, got $(typeof(channel))"))
    end
    if !isopen(channel)
        throw(ArgumentError("provided channel must be open"))
    end
    if !Base.isbuffered(channel)
        # Every delivery refuses unbuffered queues (a `put!` could block), so
        # accepting one would silently drop every published value.
        throw(ArgumentError("provided channel must be buffered"))
    end
    return channel
end

function validate_policy(policy::Symbol)
    if !(policy in POLICIES)
        throw(ArgumentError(
            "unknown delivery policy `$policy` (expected one of $(join(POLICIES, ", ")))"))
    end
    return policy
end

function register!(broker::Broker{T}, sub::Subscription{T}) where {T}
    lock(broker.lock) do
        # Only pay for pruning when the capacity check might actually need the
        # reclaimed slots; below capacity, registration is O(1).
        if broker.count >= broker.cap
            prune!(broker)
        end
        if broker.count >= broker.cap
            throw(CapacityError(broker.cap))
        end
        if isnothing(sub.topic)
            push!(broker.patterns, sub)
        else
            push!(get!(broker.exact, sub.topic, Subscription{T}[]), sub)
        end
        broker.count += 1
    end
    return sub
end

function new_subscription(broker::Broker{T}, label, matcher::SubscriptionMatcher,
                          callback, policy, csize, channel) where {T}
    validate_policy(policy)
    if !isnothing(callback) && !(callback isa Function)
        throw(ArgumentError("callback must be a function or nothing"))
    end
    queue = make_queue(T, channel, csize)
    return Subscription{T}(next_id(broker), string(label), nothing, matcher, queue,
                           callback, policy, Atomic{Int}(0), Atomic{Bool}(true))
end

"""
    subscribe!(broker, topic::AbstractString; csize=64, policy=:drop_newest, callback=nothing, channel=nothing)

Subscribe to an exact topic. Returns the `Subscription{T}`; the caller owns its
queue (`take!` values from `sub.queue`) and ends it with `unsubscribe!` or
`Base.close(sub)`.

`channel` may be a pre-created `Channel{T}` used as the queue — that is how a
caller can write an initial frame (e.g. an acknowledgement) *before* registering,
without any gap in which a concurrent publish could overtake it. The channel
must be open and buffered.
"""
function subscribe!(
        broker::Broker{T}, 
        topic::AbstractString;
        csize::Integer=64, 
        policy::Symbol=:drop_newest,
        callback=nothing, 
        channel=nothing, 
        label=nothing) where {T}

    key = String(topic)
    sub_label = isnothing(label) ? key : label
    sub = new_subscription(broker, sub_label, TopicMatcher(key), callback, policy, csize, channel)
    sub.topic = key
    return register!(broker, sub)
end

"""
    subscribe!(broker, pattern::Regex; label="", csize=64, policy=:drop_newest, callback=nothing, channel=nothing)

Subscribe to every topic matching `pattern` with `occursin`.
"""
function subscribe!(
        broker::Broker{T}, 
        pattern::Regex;
        csize::Integer=64, 
        policy::Symbol=:drop_newest,
        callback=nothing, 
        channel=nothing, 
        label="") where {T}

    sub_label = isempty(label) ? pattern : label,
    sub = new_subscription(broker, sub_label, RegexMatcher(pattern), callback, policy, csize, channel)
    return register!(broker, sub)
end

"""
    subscribe!(broker, predicate::Function; label="", csize=64, policy=:drop_newest, callback=nothing, channel=nothing)

Subscribe with a value-only predicate `predicate(value) -> Bool`, matched
against every published value regardless of topic. This is the hook protocol
adapters use to implement per-subscription filters.
"""
function subscribe!(
        broker::Broker{T}, 
        predicate::Function;
        csize::Integer=64, 
        policy::Symbol=:drop_newest,
        callback=nothing, 
        channel=nothing, 
        label="") where {T}
        
    sub_label = isempty(label) ? predicate : label
    sub = new_subscription(broker, sub_label, PredicateMatcher(predicate), callback, policy, csize, channel)
    return register!(broker, sub)
end

"""
    unsubscribe!(broker, sub) -> Bool

Remove `sub` from `broker` and close its queue (releasing a consumer blocked in
`take!`). Returns `true` when the subscription was registered, `false` when it
was already gone; only a subscription found in this broker is deactivated and
closed. Idempotent.
"""
function unsubscribe!(broker::Broker{T}, sub::Subscription{T})::Bool where {T}
    removed = lock(broker.lock) do
        found = false
        if !isnothing(sub.topic)
            subs = get(broker.exact, sub.topic, nothing)
            if !isnothing(subs)
                index = findfirst(candidate -> candidate === sub, subs)
                if !isnothing(index)
                    deleteat!(subs, index)
                    if isempty(subs)
                        delete!(broker.exact, sub.topic)
                    end
                    found = true
                end
            end
        else
            index = findfirst(candidate -> candidate === sub, broker.patterns)
            if !isnothing(index)
                deleteat!(broker.patterns, index)
                found = true
            end
        end
        if found
            broker.count -= 1
            sub.active[] = false
            close(sub.queue)
        end
        found
    end
    return removed
end

"""
    publish!(broker, topic, value) -> Int

Deliver `value` to every subscriber whose topic matches, non-blocking. Returns
the number of queues the value was enqueued into (a `:drop_newest` drop or a
`:disconnect` closure does not count). Callbacks are observers, not consumers:
they fire for every matching value after the lock is released, including values
their own queue dropped. Callback errors are logged and swallowed.
"""
function publish!(broker::Broker{T}, topic::AbstractString, value::T)::Int where {T}
    key = String(topic)
    callbacks = Tuple{Function,String}[]
    delivered = 0

    lock(broker.lock) do
        exact_subs = get(broker.exact, key, nothing)
        if !isnothing(exact_subs)
            if any(isdead, exact_subs)
                broker.count -= sweep_dead!(exact_subs)
                if isempty(exact_subs)
                    delete!(broker.exact, key)
                    exact_subs = nothing
                end
            end
            if !isnothing(exact_subs)
                for sub in exact_subs
                    if isdead(sub)
                        continue
                    end
                    if deliver!(sub, value)
                        delivered += 1
                    end
                    if !isnothing(sub.callback)
                        push!(callbacks, (sub.callback, key))
                    end
                end
            end
        end

        if !isempty(broker.patterns)
            if any(isdead, broker.patterns)
                broker.count -= sweep_dead!(broker.patterns)
            end
            for sub in broker.patterns
                if isdead(sub)
                    continue
                end
                matched = try
                    matches(sub.matcher, key, value)
                catch error
                    @warn "PubSub matcher failed" label=sub.label exception=(error, catch_backtrace())
                    false
                end
                if !matched
                    continue
                end
                if deliver!(sub, value)
                    delivered += 1
                end
                if !isnothing(sub.callback)
                    push!(callbacks, (sub.callback, key))
                end
            end
        end

        # Amortized full sweep: reclaim records that died on topics this
        # publish did not touch. Atomic-only, so the hot path stays free of
        # channel locks.
        broker.publishes += 1
        if broker.publishes >= SWEEP_INTERVAL
            broker.publishes = 0
            sweep_broker!(broker)
        end
    end

    # Snapshot-then-invoke outside the lock, so a callback may itself
    # subscribe!/unsubscribe!/publish! without deadlocking.
    for (callback, labeled) in callbacks
        try
            callback(labeled, value)
        catch error
            @warn "PubSub callback failed" topic=labeled exception=(error, catch_backtrace())
        end
    end

    return delivered
end

"""
    subscribers(broker) -> Int

The number of active subscriptions, after pruning dead records.
"""
function subscribers(broker::Broker)::Int
    return lock(broker.lock) do
        prune!(broker)
        broker.count
    end
end

"""
    close_all!(broker)

End every subscription: queues are closed (buffered values stay drainable) and
the registry is emptied. Called during shutdown.
"""
function close_all!(broker::Broker)
    lock(broker.lock) do
        for (_, subs) in broker.exact
            for sub in subs
                sub.active[] = false
                close(sub.queue)
            end
        end
        for sub in broker.patterns
            sub.active[] = false
            close(sub.queue)
        end
        empty!(broker.exact)
        empty!(broker.patterns)
        broker.count = 0
    end
    return nothing
end

end
