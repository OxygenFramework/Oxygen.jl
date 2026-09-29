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

# Process-unique ids for introspection/logging. Only uniqueness within a process
# is needed (the id is not a wire identifier).
const _NEXT_ID = Atomic{UInt64}(0)
next_id() = "sub-" * string(atomic_add!(_NEXT_ID, UInt64(1)))

"""
    Subscription{T}

One subscriber's view of the broker: a bounded queue carrying values of type
`T`, an optional in-process callback, and lifecycle flags.

# Fields
- `id::String`: process-unique id, for logs/introspection
- `label::String`: human-readable label (the topic, or the given label)
- `topic::Union{Nothing,String}`: exact topic for fast-path subscriptions
- `matcher::Function`: `(topic, value) -> Bool`, the pattern/predicate test
- `queue::Channel{T}`: the bounded delivery queue (a pre-created channel may be
  supplied so an acknowledgement can be written into it before registration)
- `callback::Union{Nothing,Function}`: `(topic, value) -> nothing`, an observer
  invoked on the publisher's task after the lock is released; it sees every
  matching value even when the queue dropped or disconnected it
- `policy::Symbol`: `:drop_newest` | `:drop_oldest` | `:disconnect`
- `drops::Threads.Atomic{Int}`: how many values `:drop_newest` discarded
- `active::Threads.Atomic{Bool}`: cleared when the subscription ends
"""
mutable struct Subscription{T}
    id       :: String
    label    :: String
    topic    :: Union{Nothing,String}
    matcher  :: Function
    queue    :: Channel{T}
    callback :: Union{Nothing,Function}
    policy   :: Symbol
    drops    :: Atomic{Int}
    active   :: Atomic{Bool}
end

Base.isopen(sub::Subscription) = sub.active[] && isopen(sub.queue)
Base.close(sub::Subscription) = (sub.active[] = false; isopen(sub.queue) && close(sub.queue); nothing)

"""
    drops(sub::Subscription) -> Int

How many values this subscription's `:drop_newest` policy has discarded.
"""
drops(sub::Subscription)::Int = sub.drops[]

"""
    Broker{T}(; cap=256)

The publish/subscribe broker. `T` is the value type delivered to subscribers;
`cap` bounds the number of active subscriptions.

Exact-topic subscriptions live in `exact` (a dictionary fast path);
regex/predicate subscriptions live in `patterns` and are scanned on publish.
All mutable state is guarded by `lock`.
"""
mutable struct Broker{T}
    lock     :: ReentrantLock
    exact    :: Dict{String,Vector{Subscription{T}}}
    patterns :: Vector{Subscription{T}}
    cap      :: Int
end

function Broker{T}(; cap::Integer=256) where {T}
    cap >= 0 || throw(ArgumentError("broker capacity must be non-negative"))
    return Broker{T}(ReentrantLock(), Dict{String,Vector{Subscription{T}}}(),
                     Subscription{T}[], Int(cap))
end

Broker(; kwargs...) = Broker{Any}(; kwargs...)

# A subscription is dead once it is closed or deactivated; dead records are
# removed opportunistically (on publish, subscribe! and subscribers) so a quiet
# broker does not leak its capacity cap.
isdead(sub::Subscription) = !sub.active[] || !isopen(sub.queue)

# Drop dead records. Callers must hold `broker.lock`.
function prune!(broker::Broker)
    if !isempty(broker.exact)
        for (topic, subs) in collect(broker.exact)
            any(isdead, subs) || continue
            filter!(sub -> !isdead(sub), subs)
            isempty(subs) && delete!(broker.exact, topic)
        end
    end
    if !isempty(broker.patterns) && any(isdead, broker.patterns)
        filter!(sub -> !isdead(sub), broker.patterns)
    end
    return broker
end

# Count live subscriptions. Callers must hold `broker.lock`.
function live_count(broker::Broker)::Int
    count = 0
    for (_, subs) in broker.exact
        for sub in subs
            isdead(sub) || (count += 1)
        end
    end
    for sub in broker.patterns
        isdead(sub) || (count += 1)
    end
    return count
end

# Non-blocking buffered put: check the buffered count under the channel's own
# lock, then `put!` under that same lock so it can never block. `Base.isfull`
# only exists on Julia >= 1.12, so the capacity check is expressed against the
# stable `data`/`sz_max` fields. Holding the channel lock is what makes it
# race-free: producers need that lock and consumers only remove items, so a
# not-full channel stays not-full through the push. Unbuffered channels are
# refused (a `put!` would wait for a taker).
function try_put!(channel::Channel{T}, value::T) where {T}
    Base.isbuffered(channel) || return false
    lock(channel)
    try
        isopen(channel) || return false
        length(channel.data) >= channel.sz_max && return false
        put!(channel, value)
        return true
    finally
        unlock(channel)
    end
end

# Non-blocking buffered take: under the channel lock an `isready` check cannot
# be overtaken by another taker (they need the same lock), so `take!` returns
# immediately. Returns `(value, true)` or `(nothing, false)`.
function try_take!(channel::Channel)
    Base.isbuffered(channel) || return nothing, false
    lock(channel)
    try
        isready(channel) || return nothing, false
        return take!(channel), true
    finally
        unlock(channel)
    end
end

# Non-blocking delivery into one subscriber's queue, applying its policy.
# Returns `true` when the value was enqueued. Callers must hold `broker.lock`.
function deliver!(sub::Subscription{T}, value::T) where {T}
    isdead(sub) && return false

    try_put!(sub.queue, value) && return true

    if sub.policy === :drop_oldest
        # Make room by discarding the oldest queued value. If there is nothing
        # to take (unbuffered queue) or the requeue still fails (closed queue),
        # the incoming value is lost too and counts as a drop.
        _, removed = try_take!(sub.queue)
        if removed && try_put!(sub.queue, value)
            return true
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
    if channel === nothing
        csize >= 0 || throw(ArgumentError("queue capacity must be non-negative"))
        return Channel{T}(csize)
    end
    channel isa Channel{T} || throw(ArgumentError(
        "provided channel must be a Channel{$T}, got $(typeof(channel))"))
    return channel
end

function validate_policy(policy::Symbol)
    policy in POLICIES || throw(ArgumentError(
        "unknown delivery policy `$policy` (expected one of $(join(POLICIES, ", ")))"))
    return policy
end

function register!(broker::Broker{T}, sub::Subscription{T}) where {T}
    lock(broker.lock) do
        prune!(broker)
        live_count(broker) >= broker.cap && throw(CapacityError(broker.cap))
        if sub.topic === nothing
            push!(broker.patterns, sub)
        else
            push!(get!(broker.exact, sub.topic, Subscription{T}[]), sub)
        end
    end
    return sub
end

function new_subscription(::Type{T}, label, matcher, callback, policy, csize, channel) where {T}
    validate_policy(policy)
    callback === nothing || callback isa Function ||
        throw(ArgumentError("callback must be a function or nothing"))
    queue = make_queue(T, channel, csize)
    return Subscription{T}(next_id(), string(label), nothing, matcher, queue,
                           callback, policy, Atomic{Int}(0), Atomic{Bool}(true))
end

"""
    subscribe!(broker, topic::AbstractString; csize=64, policy=:drop_newest, callback=nothing, channel=nothing)

Subscribe to an exact topic. Returns the `Subscription{T}`; the caller owns its
queue (`take!` values from `sub.queue`) and ends it with `unsubscribe!` or
`Base.close(sub)`.

`channel` may be a pre-created `Channel{T}` used as the queue — that is how a
caller can write an initial frame (e.g. an acknowledgement) *before* registering,
without any gap in which a concurrent publish could overtake it.
"""
function subscribe!(broker::Broker{T}, topic::AbstractString;
                    csize::Integer=64, policy::Symbol=:drop_newest,
                    callback=nothing, channel=nothing, label=nothing) where {T}
    key = String(topic)
    sub = new_subscription(T, label === nothing ? key : label,
                           (t, _) -> t == key, callback, policy, csize, channel)
    sub.topic = key
    return register!(broker, sub)
end

"""
    subscribe!(broker, pattern::Regex; label="", csize=64, policy=:drop_newest, callback=nothing, channel=nothing)

Subscribe to every topic matching `pattern` with `occursin`.
"""
function subscribe!(broker::Broker{T}, pattern::Regex;
                    csize::Integer=64, policy::Symbol=:drop_newest,
                    callback=nothing, channel=nothing, label="") where {T}
    sub = new_subscription(T, isempty(label) ? pattern : label,
                           (t, _) -> occursin(pattern, t), callback, policy, csize, channel)
    return register!(broker, sub)
end

"""
    subscribe!(broker, predicate::Function; label="", csize=64, policy=:drop_newest, callback=nothing, channel=nothing)

Subscribe with a value-only predicate `predicate(value) -> Bool`, matched
against every published value regardless of topic. This is the hook protocol
adapters use to implement per-subscription filters.
"""
function subscribe!(broker::Broker{T}, predicate::Function;
                    csize::Integer=64, policy::Symbol=:drop_newest,
                    callback=nothing, channel=nothing, label="") where {T}
    sub = new_subscription(T, isempty(label) ? predicate : label,
                           (_, value) -> predicate(value) === true,
                           callback, policy, csize, channel)
    return register!(broker, sub)
end

"""
    unsubscribe!(broker, sub) -> Bool

Remove `sub` from `broker` and close its queue (releasing a consumer blocked in
`take!`). Returns `true` when the subscription was registered, `false` when it
was already gone. Idempotent.
"""
function unsubscribe!(broker::Broker{T}, sub::Subscription{T})::Bool where {T}
    removed = lock(broker.lock) do
        found = false
        if sub.topic !== nothing
            subs = get(broker.exact, sub.topic, nothing)
            if subs !== nothing
                index = findfirst(candidate -> candidate === sub, subs)
                if index !== nothing
                    deleteat!(subs, index)
                    isempty(subs) && delete!(broker.exact, sub.topic)
                    found = true
                end
            end
        else
            index = findfirst(candidate -> candidate === sub, broker.patterns)
            if index !== nothing
                deleteat!(broker.patterns, index)
                found = true
            end
        end
        sub.active[] = false
        isopen(sub.queue) && close(sub.queue)
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
        prune!(broker)

        exact_subs = get(broker.exact, key, nothing)
        if exact_subs !== nothing
            for sub in exact_subs
                isdead(sub) && continue
                deliver!(sub, value) && (delivered += 1)
                sub.callback === nothing || push!(callbacks, (sub.callback, key))
            end
        end

        for sub in broker.patterns
            isdead(sub) && continue
            matched = try
                sub.matcher(key, value)
            catch error
                @warn "PubSub matcher failed" label=sub.label exception=(error, catch_backtrace())
                false
            end
            matched || continue
            deliver!(sub, value) && (delivered += 1)
            sub.callback === nothing || push!(callbacks, (sub.callback, key))
        end

        prune!(broker)
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
        live_count(broker)
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
                isopen(sub.queue) && close(sub.queue)
            end
        end
        for sub in broker.patterns
            sub.active[] = false
            isopen(sub.queue) && close(sub.queue)
        end
        empty!(broker.exact)
        empty!(broker.patterns)
    end
    return nothing
end

end
