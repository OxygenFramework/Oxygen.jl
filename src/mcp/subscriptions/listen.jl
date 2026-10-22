# Modern `subscriptions/listen` streams and their wire serialization.
# Included into `MCP.Subscriptions` by `../subscriptions.jl`.

# ----------------------------------------------------------------------------
# Listen streams
# ----------------------------------------------------------------------------

"""
    ListenRecord

One registered listen stream.

- `id`: the JSON-RPC id (String or Int), also the subscription id
- `filter`: the honored filter (the broker predicate closes over it)
- `sub`: the broker subscription (its queue is `stream.channel`)
- `stream`: the transport-facing event stream
- `cancellable`: true for routeless (stdio) streams only; an in-band
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

"""
    ListenCall

A live `subscriptions/listen` stream returned by dispatch. `stream.channel` is
the broker subscription queue; `id` is the listen request's JSON-RPC id, also
used as the wire subscription id, and `record` is the registered `ListenRecord`.
Teardown hands the record back to the registry directly: JSON-RPC ids are unique
per connection, not per server, so looking a stream up by id would let one
connection tear down another's.
"""
struct ListenCall
    stream :: EventStream
    id     :: Any
    record :: ListenRecord
end

# JSON-RPC ids are String or Int; stringifying makes ids comparable regardless
# of wire form. The registry is not keyed by id: ids are only unique within one
# connection, so cross-client duplicates are legal. Only the routeless (stdio)
# records (all owned by the single stdio client) are addressable by id.
listen_key(id) = string(id)

# The stdio (cancellable) record carrying `id`, if any. HTTP streams are not
# addressable by id: two clients sharing an id are two independent streams, and
# neither may cancel the other. Callers hold `subscriptions_lock`.
function stdio_listen(ctx::ServerContext, id)
    key = listen_key(id)
    for record in ctx.mcp.listens
        if record.cancellable && listen_key(record.id) == key
            return record
        end
    end
    return nothing
end

# Remove records whose stream closed without a transport teardown (defensive:
# the transports unregister in their `finally`). Callers hold subscriptions_lock.
function sweep_listens!(ctx::ServerContext)
    if isempty(ctx.mcp.listens)
        return nothing
    end
    for record in collect(ctx.mcp.listens)
        if !isopen(record.sub)
            delete!(ctx.mcp.listens, record)
        end
    end
    return nothing
end

"""
    listen_admission(ctx, id; cancellable, record=nothing) :: Symbol

The admission decision for a listen stream: `:ok`, `:capacity`, or `:duplicate`.
When `record` is given it is registered on success. A `cancellable` stream (a
routeless stdio stream) also rejects duplicate ids, because all of one
connection's streams share the registry; on HTTP each listen stream is its own
connection, so two clients using the same id are two independent subscriptions.
"""
function listen_admission(
    ctx::ServerContext,
    id;
    cancellable::Bool,
    record::Union{Nothing,ListenRecord}=nothing) :: Symbol

    return lock(ctx.mcp.subscriptions_lock) do
        sweep_listens!(ctx)
        if length(ctx.mcp.listens) >= MAX_LISTEN_SUBSCRIPTIONS
            return :capacity
        end
        if cancellable && !isnothing(stdio_listen(ctx, id))
            return :duplicate
        end
        if !isnothing(record)
            push!(ctx.mcp.listens, record)
        end
        return :ok
    end
end

function listen_error(id, reason::Symbol)
    if reason === :capacity
        return error_body(id, MCP_INTERNAL_ERROR, LISTEN_LIMIT_MESSAGE), 400
    end
    return error_body(id, MCP_INVALID_REQUEST, LISTEN_DUPLICATE_MESSAGE), 400
end

"""
    listen_call(ctx, req, id, params) :: Union{Tuple{Dict,Int},Tuple{ListenCall,Int}}

Open a `subscriptions/listen` stream: validate the filter and id, enforce the
capacity limit (and, on stdio, the duplicate-id limit), enqueue the
acknowledgement as the stream's FIRST message, register the broker subscription,
and return the `ListenCall`. A violation is rejected with a JSON-RPC error
instead of a stream.
"""
function listen_call(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params)
    requested = parse_subscription_filter(get(params, "notifications", nothing))
    if !(requested isa SubscriptionFilter)
        return error_body(id, MCP_INVALID_PARAMS,
                          "Invalid subscriptions/listen filter: $requested"), 400
    end

    if !(id isa Union{String,Int})
        return error_body(id, MCP_INVALID_REQUEST,
                          "subscriptions/listen requires a string or integer request id"), 400
    end
    if id isa String && ncodeunits(id) > MAX_SUBSCRIPTION_ID_LENGTH
        return error_body(
            id, MCP_INVALID_REQUEST,
            "subscriptions/listen id exceeds $(MAX_SUBSCRIPTION_ID_LENGTH) bytes"), 400
    end

    key = listen_key(id)

    # Capacity/duplicate precheck. The authoritative check runs at registration;
    # this one avoids building a stream that is certain to be rejected. The
    # sweep keeps 64 dead streams from denying the surface on a quiet server.
    precheck = listen_admission(ctx, id; cancellable=isnothing(req))
    if precheck !== :ok
        return listen_error(id, precheck)
    end

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
        if !(error isa PubSub.CapacityError)
            rethrow()
        end
        close(channel)
        return error_body(id, MCP_INTERNAL_ERROR, LISTEN_LIMIT_MESSAGE), 400
    end

    stream = EventStream(channel, nothing)
    record = ListenRecord(id, honored, sub, stream, isnothing(req))

    registered = listen_admission(ctx, id; cancellable=record.cancellable, record=record)
    if registered !== :ok
        PubSub.unsubscribe!(mcp_broker, sub)
        return listen_error(id, registered)
    end

    return ListenCall(stream, id, record), 200
end

"""
    remove_listen!(ctx, record::ListenRecord)

Tombstone and remove a listen record: the transport hands back the record it
owns because the stream is closed (or about to close). Removing by record (not
by id) is what keeps one connection's teardown from pruning another
connection's stream when both use the same JSON-RPC id.
"""
function remove_listen!(ctx::ServerContext, record::ListenRecord)
    lock(ctx.mcp.subscriptions_lock) do
        delete!(ctx.mcp.listens, record)
    end
    record.sub.active[] = false
    return nothing
end

"""
    cancel_listen!(ctx, id) :: Bool

Cancel a routeless (stdio) listen stream by its request id, the
`notifications/cancelled` path. Per JSON-RPC cancellation semantics no response
is sent. Only stdio streams are addressable by id; HTTP streams are never
cancellable this way (see `ListenRecord.cancellable`). Returns `true` when an
active cancellable stream was cancelled.
"""
function cancel_listen!(ctx::ServerContext, id) :: Bool
    record = lock(ctx.mcp.subscriptions_lock) do
        found = stdio_listen(ctx, id)
        if isnothing(found)
            return nothing
        end
        delete!(ctx.mcp.listens, found)
        return found
    end

    if isnothing(record)
        return false
    end
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
        found = collect(ctx.mcp.listens)
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
            # The transport may have closed the channel first; either way the
            # stream is already ending.
        end
    end
    return nothing
end

# The JSON-RPC response that closes a listen stream gracefully.
function closing_body(ctx::ServerContext, id) :: Dict{String,Any}
    result = result_envelope(LATEST_MODERN_SPEC, ctx, Dict{String,Any}())
    meta = result[META_KEY]
    meta[META_SUBSCRIPTION_ID] = id
    return result_body(id, result)
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
function serialize_listen_event(subscription_id, event::SubscriptionNotification) :: Dict{String,Any}

    params = Dict{String,Any}(event.params)
    existing = get(params, META_KEY, nothing)
    meta = existing isa AbstractDict ?
        string_keyed(existing) : Dict{String,Any}()
    meta[META_SUBSCRIPTION_ID] = subscription_id
    params[META_KEY] = meta
    return notification(event.method, params)
end

"""
    listen_frame(call, event) :: (body, terminal)

Map one `subscriptions/listen` stream event to the JSON-RPC message a transport
should write and whether the stream ended. Shared by the HTTP and stdio listen
transports.
"""
function listen_frame(call::ListenCall, event) :: Tuple{Dict{String,Any},Bool}
    if event isa FinalEvent
        return event.value, true
    elseif event isa ErrorEvent
        return error_body(call.id, MCP_INTERNAL_ERROR, sprint(showerror, event.error)), true
    end
    return serialize_listen_event(call.id, event), false
end
