# Server-initiated change notifications: modern `subscriptions/listen` streams,
# legacy `resources/subscribe` delivery, and the `notify_*` broadcast APIs.
# Included into the `MCP` module by `../mcp.jl`, after `resources.jl`.
#
# The generic fan-out engine lives in `../pubsub.jl`. This file owns the MCP
# event model, the per-stream filter, the listen registry, and the wire shapes.
# A listen stream's queue IS its broker subscription queue: the broker pushes
# `StreamEvent`s into it, the transport task pumps them out, and closing the
# queue (disconnect/cancellation) makes the broker prune the subscription.
#
# Lock ordering: `broker.lock` may be held while this file takes
# `subscriptions_lock` (the legacy filter reads the subscription set under it);
# no code may hold `subscriptions_lock` while acquiring `broker.lock`.

# ----------------------------------------------------------------------------
# Event model
# ----------------------------------------------------------------------------

"""
    SubscriptionNotification(method, params, uri=nothing)

A server-initiated JSON-RPC notification broadcast through the MCP broker.
`uri` is set for `notifications/resources/updated` so per-stream filters can
match without decoding `params`.
"""
struct SubscriptionNotification <: StreamEvent
    method :: String
    params :: Dict{String,Any}
    uri    :: Union{Nothing,String}
end

function SubscriptionNotification(method::AbstractString, params::AbstractDict)::SubscriptionNotification
    return SubscriptionNotification(String(method), Dict{String,Any}(String(k) => v for (k, v) in params), nothing)
end

# The broker payload is the generic engine's event type, so a listen stream's
# queue can be the broker subscription queue verbatim (no bridge task).
const MCPBroker = PubSub.Broker{StreamEvent}

# Reserved `_meta` key carrying the listen request id on every stream message.
const META_SUBSCRIPTION_ID = "io.modelcontextprotocol/subscriptionId"

# Limits: each subscription pins a record, a queue, and (on HTTP) an open
# connection for an unbounded lifetime, so the count and the id size are bounded.
const MAX_LISTEN_SUBSCRIPTIONS   = 64
const MAX_RESOURCE_SUBSCRIPTIONS = 256
const MAX_SUBSCRIPTION_ID_LENGTH = 128
const LISTEN_BACKLOG_CAP         = 256
const LEGACY_NOTIFICATION_CAP    = 1000

# ----------------------------------------------------------------------------
# Filter
# ----------------------------------------------------------------------------

"""
    SubscriptionFilter(; tools_list_changed=false, prompts_list_changed=false,
                       resources_list_changed=false, resource_uris=Set{String}())

The notification types a `subscriptions/listen` stream opted into. A server
MUST NOT send notification types the client did not request, so every delivery
is checked against this filter.
"""
Base.@kwdef struct SubscriptionFilter
    tools_list_changed     :: Bool        = false
    prompts_list_changed   :: Bool        = false
    resources_list_changed :: Bool        = false
    resource_uris          :: Set{String} = Set{String}()
end

"""
    parse_subscription_filter(notifications) :: Union{SubscriptionFilter,String}

Validate and parse the `notifications` filter object of a `subscriptions/listen`
request. Returns the parsed filter, or a violation message the caller rejects
with `-32602`: the filter must be an object, the `*ListChanged` flags booleans,
`resourceSubscriptions` an array of at most `MAX_RESOURCE_SUBSCRIPTIONS`
strings, and at least one notification type must be requested. Unknown keys are
ignored for forward compatibility.
"""
function parse_subscription_filter(notifications)::Union{SubscriptionFilter,String}
    notifications isa AbstractDict || return "notifications must be an object"

    for key in ("toolsListChanged", "promptsListChanged", "resourcesListChanged")
        haskey(notifications, key) && !(notifications[key] isa Bool) &&
            return "$key must be a boolean"
    end

    uris = Set{String}()
    if haskey(notifications, "resourceSubscriptions")
        subscriptions = notifications["resourceSubscriptions"]
        subscriptions isa AbstractVector || return "resourceSubscriptions must be an array of strings"
        length(subscriptions) > MAX_RESOURCE_SUBSCRIPTIONS &&
            return "resourceSubscriptions exceeds the limit of $(MAX_RESOURCE_SUBSCRIPTIONS) URIs"
        for uri in subscriptions
            uri isa AbstractString || return "resourceSubscriptions must be an array of strings"
            push!(uris, String(uri))
        end
    end

    filter = SubscriptionFilter(
        tools_list_changed     = get(notifications, "toolsListChanged", false) === true,
        prompts_list_changed   = get(notifications, "promptsListChanged", false) === true,
        resources_list_changed = get(notifications, "resourcesListChanged", false) === true,
        resource_uris          = uris,
    )

    if !(filter.tools_list_changed || filter.prompts_list_changed ||
         filter.resources_list_changed) && isempty(filter.resource_uris)
        return "at least one notification type must be requested"
    end
    return filter
end

"""
    filter_to_wire(filter) :: Dict

Serialize the honored filter subset to the `notifications` field of the
acknowledgement. Types not subscribed are omitted; URIs are emitted sorted (the
set has no stable order).
"""
function filter_to_wire(filter::SubscriptionFilter)::Dict{String,Any}
    wire = Dict{String,Any}()
    filter.tools_list_changed     && (wire["toolsListChanged"] = true)
    filter.prompts_list_changed   && (wire["promptsListChanged"] = true)
    filter.resources_list_changed && (wire["resourcesListChanged"] = true)
    isempty(filter.resource_uris) || (wire["resourceSubscriptions"] = sort!(collect(filter.resource_uris)))
    return wire
end

"""
    filter_wants(filter, event) :: Bool

Whether `event` was opted into by `filter`.
"""
function filter_wants(filter::SubscriptionFilter, event::SubscriptionNotification)::Bool
    method = event.method
    if method == "notifications/tools/list_changed"
        return filter.tools_list_changed
    elseif method == "notifications/prompts/list_changed"
        return filter.prompts_list_changed
    elseif method == "notifications/resources/list_changed"
        return filter.resources_list_changed
    elseif method == "notifications/resources/updated"
        return event.uri !== nothing && event.uri in filter.resource_uris
    end
    return false
end

# Whether the server currently advertises the `listChanged` capability for a
# kind. Kept as a function (not a constant) because the registries are mutable.
function list_changed_capable(ctx::ServerContext, kind::Symbol)::Bool
    kind === :tools     && return true
    kind === :prompts   && return !isempty(ctx.mcp.prompts)
    kind === :resources && return has_resources(ctx)
    return false
end

has_resources(ctx::ServerContext)::Bool =
    !isempty(ctx.mcp.resources) || !isempty(ctx.mcp.resource_templates)

"""
    honored_filter(ctx, requested) :: SubscriptionFilter

Mask a requested filter by the capabilities this server advertises: types it
cannot deliver are omitted from the acknowledgement, so the ack is the honest
source of what will actually be sent.
"""
function honored_filter(ctx::ServerContext, requested::SubscriptionFilter)::SubscriptionFilter
    resources = has_resources(ctx)
    return SubscriptionFilter(
        tools_list_changed     = requested.tools_list_changed && list_changed_capable(ctx, :tools),
        prompts_list_changed   = requested.prompts_list_changed && list_changed_capable(ctx, :prompts),
        resources_list_changed = requested.resources_list_changed && list_changed_capable(ctx, :resources),
        resource_uris          = resources ? requested.resource_uris : Set{String}(),
    )
end

# ----------------------------------------------------------------------------
# Broker
# ----------------------------------------------------------------------------

"""
    broker(ctx) :: MCPBroker

The context's notification broker, created lazily (the `MCPContext` is built
before this module is defined, so the field is an untyped `Ref`).
"""
function broker(ctx::ServerContext)::MCPBroker
    existing = ctx.mcp.broker[]
    existing isa MCPBroker && return existing

    return lock(ctx.mcp.subscriptions_lock) do
        existing = ctx.mcp.broker[]
        existing isa MCPBroker && return existing
        created = MCPBroker(; cap=MAX_LISTEN_SUBSCRIPTIONS)
        ctx.mcp.broker[] = created
        return created
    end
end

# ----------------------------------------------------------------------------
# Listen streams
# ----------------------------------------------------------------------------

"""
    ListenCall

A live `subscriptions/listen` stream returned by dispatch. `stream.channel` is
the broker subscription queue; `id` is the listen request's JSON-RPC id, also
used as the wire subscription id.
"""
struct ListenCall
    stream :: EventStream
    id     :: Any
end

"""
    ListenRecord

One registered listen stream.

- `id`: the JSON-RPC id (String or Int), also the subscription id
- `filter`: the honored filter (the broker predicate closes over it)
- `sub`: the broker subscription (its queue is `stream.channel`)
- `stream`: the transport-facing event stream
- `cancellable`: true for routeless (stdio) streams only — an in-band
  `notifications/cancelled` must never be honored for an HTTP stream, where the
  message can arrive on any connection and would let one client kill another
  client's stream by guessing its id
"""
mutable struct ListenRecord
    id          :: Any
    filter      :: SubscriptionFilter
    sub         :: PubSub.Subscription
    stream      :: EventStream
    cancellable :: Bool
end

# JSON-RPC ids are String or Int; stringifying makes the `listens` dictionary
# keyable. Collisions between an Int and its string form are rejected as
# duplicates, which is conservative and load-bearing on stdio.
listen_key(id) = string(id)

# Remove records whose stream closed without a transport teardown (defensive:
# the transports unregister in their `finally`). Callers hold subscriptions_lock.
function sweep_listens!(ctx::ServerContext)
    isempty(ctx.mcp.listens) && return nothing
    for (key, record) in collect(ctx.mcp.listens)
        isopen(record.sub) || delete!(ctx.mcp.listens, key)
    end
    return nothing
end

"""
    listen_call(ctx, req, id, params) :: Union{Tuple{Dict,Int},Tuple{ListenCall,Int}}

Open a `subscriptions/listen` stream: validate the filter and id, enforce the
capacity and duplicate-id limits, enqueue the acknowledgement as the stream's
FIRST message, register the broker subscription, and return the `ListenCall`.
A violation is rejected with a JSON-RPC error instead of a stream.
"""
function listen_call(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params)
    requested = parse_subscription_filter(get(params, "notifications", nothing))
    requested isa SubscriptionFilter || return error_body(
        id, MCP_INVALID_PARAMS, "Invalid subscriptions/listen filter: $requested"), 400

    id isa Union{String,Int} || return error_body(
        id, MCP_INVALID_REQUEST, "subscriptions/listen requires a string or integer request id"), 400
    id isa String && ncodeunits(id) > MAX_SUBSCRIPTION_ID_LENGTH && return error_body(
        id, MCP_INVALID_REQUEST, "subscriptions/listen id exceeds $(MAX_SUBSCRIPTION_ID_LENGTH) bytes"), 400

    key = listen_key(id)

    # Capacity/duplicate precheck. The authoritative check runs at registration;
    # this one avoids building a stream that is certain to be rejected. The
    # sweep keeps 64 dead streams from denying the surface on a quiet server.
    precheck = lock(ctx.mcp.subscriptions_lock) do
        sweep_listens!(ctx)
        if length(ctx.mcp.listens) >= MAX_LISTEN_SUBSCRIPTIONS
            return :capacity
        end
        return haskey(ctx.mcp.listens, key) ? :duplicate : :ok
    end
    precheck === :capacity && return error_body(
        id, MCP_INTERNAL_ERROR,
        "subscriptions/listen: active subscription limit reached ($(MAX_LISTEN_SUBSCRIPTIONS))"), 400
    precheck === :duplicate && return error_body(
        id, MCP_INVALID_REQUEST, "subscriptions/listen id duplicates an active subscription"), 400

    honored = honored_filter(ctx, requested)
    mcp_broker = broker(ctx)

    # The acknowledgement is enqueued before registration, and all delivery
    # happens under the broker lock with FIFO queues, so no notification can
    # precede the ack.
    channel = Channel{StreamEvent}(LISTEN_BACKLOG_CAP)
    put!(channel, SubscriptionNotification(
        "notifications/subscriptions/acknowledged",
        Dict{String,Any}("notifications" => filter_to_wire(honored))))

    sub = try
        PubSub.subscribe!(mcp_broker,
            event -> event isa SubscriptionNotification && filter_wants(honored, event);
            channel=channel, policy=:disconnect, label="listen:$key")
    catch error
        # The broker cap is a safety net behind the registry cap; a racing
        # registration can exhaust it between the precheck and here.
        error isa PubSub.CapacityError || rethrow()
        close(channel)
        return error_body(id, MCP_INTERNAL_ERROR,
            "subscriptions/listen: active subscription limit reached ($(MAX_LISTEN_SUBSCRIPTIONS))"), 400
    end

    stream = EventStream(channel, nothing)
    record = ListenRecord(id, honored, sub, stream, req === nothing)

    registered = lock(ctx.mcp.subscriptions_lock) do
        sweep_listens!(ctx)
        if length(ctx.mcp.listens) >= MAX_LISTEN_SUBSCRIPTIONS
            return :capacity
        end
        return haskey(ctx.mcp.listens, key) ? :duplicate : (ctx.mcp.listens[key] = record; :ok)
    end

    if registered !== :ok
        PubSub.unsubscribe!(mcp_broker, sub)
        return registered === :capacity ? error_body(
            id, MCP_INTERNAL_ERROR,
            "subscriptions/listen: active subscription limit reached ($(MAX_LISTEN_SUBSCRIPTIONS))") :
            error_body(id, MCP_INVALID_REQUEST, "subscriptions/listen id duplicates an active subscription"), 400
    end

    return ListenCall(stream, id), 200
end

"""
    detach_listen!(ctx, id) :: Union{Nothing,ListenRecord}

Remove the listen record for `id` from the registry (if present) and return it.
No channel or broker operations happen here.
"""
function detach_listen!(ctx::ServerContext, id)::Union{Nothing,ListenRecord}
    return lock(ctx.mcp.subscriptions_lock) do
        pop!(ctx.mcp.listens, listen_key(id), nothing)
    end
end

"""
    remove_listen!(ctx, id)

Tombstone and remove a listen record: the transport has already closed (or is
about to close) the stream.
"""
function remove_listen!(ctx::ServerContext, id)
    record = detach_listen!(ctx, id)
    if record !== nothing
        record.sub.active[] = false
    end
    return nothing
end

"""
    cancel_listen!(ctx, id) :: Bool

Cancel a routeless (stdio) listen stream by its request id — the
`notifications/cancelled` path. Per JSON-RPC cancellation semantics no response
is sent. Returns `true` when an active cancellable stream was cancelled.
"""
function cancel_listen!(ctx::ServerContext, id)::Bool
    record = lock(ctx.mcp.subscriptions_lock) do
        key = listen_key(id)
        found = get(ctx.mcp.listens, key, nothing)
        (found === nothing || !found.cancellable) && return nothing
        delete!(ctx.mcp.listens, key)
        return found
    end

    record === nothing && return false
    record.sub.active[] = false
    cancel_stream!(record.stream)
    return true
end

"""
    close_listens!(ctx)

End all listen streams gracefully: each stream receives the JSON-RPC response
to its originating listen request (a complete modern result tagged with its
subscription id and carrying `serverInfo`), so a client can distinguish an
orderly server shutdown from an abrupt drop. Called during `terminate`.
"""
function close_listens!(ctx::ServerContext)
    records = lock(ctx.mcp.subscriptions_lock) do
        found = collect(values(ctx.mcp.listens))
        empty!(ctx.mcp.listens)
        return found
    end

    for record in records
        record.sub.active[] = false
        # The queue is bounded; at shutdown a full backlog must not block the
        # closing result indefinitely. A dropped final frame degrades to an
        # abrupt close, which is still correct.
        PubSub.try_put!(record.stream.channel, FinalEvent(closing_body(ctx, record.id)))
        try
            close(record.stream.channel)
        catch
        end
    end
    return nothing
end

# The JSON-RPC response that closes a listen stream gracefully.
function closing_body(ctx::ServerContext, id)::Dict{String,Any}
    result = modern_envelope(ctx, Dict{String,Any}())
    meta = result[META_KEY]
    meta[META_SUBSCRIPTION_ID] = id
    return result_body(id, result)
end

# ----------------------------------------------------------------------------
# Broadcast / notify
# ----------------------------------------------------------------------------

"""
    broadcast_notification(ctx, event) :: Int

Publish a server notification to every matching subscriber (listen streams and
the legacy sinks). Returns the number of queues it was enqueued into.
"""
function broadcast_notification(ctx::ServerContext, event::SubscriptionNotification)::Int
    return PubSub.publish!(broker(ctx), event.method, event)
end

"""
    notify_resource_updated(ctx, uri) :: Int

Announce that a resource's contents changed.
"""
function notify_resource_updated(ctx::ServerContext, uri::AbstractString)::Int
    target = String(uri)
    return broadcast_notification(ctx, SubscriptionNotification(
        "notifications/resources/updated", Dict{String,Any}("uri" => target), target))
end

"""
    notify_list_changed(ctx, kind) :: Int

Announce that a component list changed (`:tools`, `:prompts` or `:resources`).
"""
function notify_list_changed(ctx::ServerContext, kind::Symbol)::Int
    kind in (:tools, :prompts, :resources) || throw(ArgumentError(
        "notify_list_changed: kind must be :tools, :prompts, or :resources"))
    return broadcast_notification(ctx, SubscriptionNotification(
        "notifications/$(kind)/list_changed", Dict{String,Any}(), nothing))
end

notify_tools_changed(ctx::ServerContext)::Int     = notify_list_changed(ctx, :tools)
notify_prompts_changed(ctx::ServerContext)::Int   = notify_list_changed(ctx, :prompts)
notify_resources_changed(ctx::ServerContext)::Int = notify_list_changed(ctx, :resources)

# ----------------------------------------------------------------------------
# Legacy delivery
# ----------------------------------------------------------------------------

# Whether a notification may be delivered on the legacy server→client channel.
# Gated on a COMPLETED handshake: `notifications/initialized` alone is not
# proof (a bare initialized sets the flag), so a negotiated version is required
# too. Resource updates additionally require the URI in the session's
# subscription set; list changes require the advertised capability.
function legacy_event_wanted(ctx::ServerContext, event::SubscriptionNotification)::Bool
    (ctx.mcp.initialized[] && ctx.mcp.handshake_complete[]) || return false

    method = event.method
    if method == "notifications/resources/updated"
        uri = event.uri
        uri === nothing && return false
        return lock(ctx.mcp.subscriptions_lock) do
            uri in ctx.mcp.legacy_subscriptions
        end
    elseif method == "notifications/tools/list_changed"
        return list_changed_capable(ctx, :tools)
    elseif method == "notifications/prompts/list_changed"
        return list_changed_capable(ctx, :prompts)
    elseif method == "notifications/resources/list_changed"
        return list_changed_capable(ctx, :resources)
    end
    return false
end

"""
    subscribe_legacy!(ctx; csize, label) :: PubSub.Subscription

Register the single broker subscription that feeds a legacy transport's
server→client channel (stdio stdout or the HTTP GET SSE sink). The caller owns
the subscription's queue and forwards its events.
"""
function subscribe_legacy!(ctx::ServerContext; csize::Integer=LEGACY_NOTIFICATION_CAP, label::String="legacy")
    return PubSub.subscribe!(broker(ctx),
        event -> event isa SubscriptionNotification && legacy_event_wanted(ctx, event);
        csize=csize, policy=:drop_newest, label=label)
end

# Legacy `resources/subscribe`: record the URI (idempotent). The URI need not
# be registered — the spec has servers acknowledge subscriptions they can
# deliver, and a template may match it later.
function subscribe_resource_legacy(ctx::ServerContext, id, params)
    uri = get(params, "uri", nothing)
    if !(uri isa AbstractString) || isempty(uri)
        return error_body(id, MCP_INVALID_PARAMS, "Missing resource URI"), 200
    end
    lock(ctx.mcp.subscriptions_lock) do
        push!(ctx.mcp.legacy_subscriptions, String(uri))
    end
    return result_body(id, Dict{String,Any}()), 200
end

# Legacy `resources/unsubscribe`: remove the URI (idempotent).
function unsubscribe_resource_legacy(ctx::ServerContext, id, params)
    uri = get(params, "uri", nothing)
    if !(uri isa AbstractString) || isempty(uri)
        return error_body(id, MCP_INVALID_PARAMS, "Missing resource URI"), 200
    end
    lock(ctx.mcp.subscriptions_lock) do
        delete!(ctx.mcp.legacy_subscriptions, String(uri))
    end
    return result_body(id, Dict{String,Any}()), 200
end

# ----------------------------------------------------------------------------
# Wire serialization
# ----------------------------------------------------------------------------

"""
    serialize_listen_event(subscription_id, event) :: Dict

Map one listen-stream event to the JSON-RPC message that carries it. The
subscription id is merged into any existing `params._meta` (never overwriting
the whole dictionary), so the ack's own metadata survives.
"""
function serialize_listen_event(subscription_id, event::SubscriptionNotification)::Dict{String,Any}
    params = Dict{String,Any}(event.params)
    existing = get(params, META_KEY, nothing)
    meta = existing isa AbstractDict ?
        Dict{String,Any}(String(k) => v for (k, v) in existing) : Dict{String,Any}()
    meta[META_SUBSCRIPTION_ID] = subscription_id
    params[META_KEY] = meta
    return notification(event.method, params)
end
