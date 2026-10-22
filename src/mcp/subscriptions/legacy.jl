# Legacy `resources/subscribe` delivery over the server-to-client channel.
# Included into `MCP.Subscriptions` by `../subscriptions.jl`.

# ----------------------------------------------------------------------------
# Legacy delivery
# ----------------------------------------------------------------------------

# Whether a notification may be delivered on the legacy server→client channel.
# Gated on a COMPLETED handshake: `notifications/initialized` alone is not
# proof (a bare initialized sets the flag), so a negotiated version is required
# too. Resource updates additionally require the URI in the client's
# subscription set; list changes require the advertised capability.
#
# Session-scoped sinks read the session's own flags and set, so concurrent
# legacy clients never observe each other's subscriptions. Sinks without a
# session (stdio and header-less HTTP) keep using the context-wide anonymous
# state, preserving the original single-session behavior.
function legacy_event_wanted(
    ctx::ServerContext,
    event::SubscriptionNotification;
    session::Union{Nothing,MCPSession}=nothing) :: Bool

    if !handshake_ready(ctx, session)
        return false
    end

    method = event.method
    if method == "notifications/resources/updated"
        uri = event.uri
        if isnothing(uri)
            return false
        end
        return legacy_subscribed(ctx, session, uri)
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
    subscribe_legacy!(ctx; csize, label, session) :: Union{Nothing,PubSub.Subscription}

Register the broker subscription that feeds a legacy transport's server→client
channel (stdio stdout or the HTTP GET SSE sink). The caller owns the
subscription's queue and forwards its events. Session-scoped sinks are tracked
on the session so `DELETE` can end them; `nothing` is returned when the session
was terminated concurrently.
"""
function subscribe_legacy!(
    ctx::ServerContext;
    csize::Integer=LEGACY_NOTIFICATION_CAP,
    label::String="legacy",
    session::Union{Nothing,MCPSession}=nothing)

    sub = PubSub.subscribe!(broker(ctx),
        event -> event isa SubscriptionNotification &&
                 legacy_event_wanted(ctx, event; session=session);
        csize=csize, policy=:drop_newest, label=label)
    if !(session isa MCPSession)
        return sub
    end
    if !add_sink!(ctx, session, sub)
        return nothing
    end
    return sub
end

# Legacy `resources/subscribe` / `resources/unsubscribe`: record or remove the
# URI (both idempotent). The URI need not be registered: the spec has servers
# acknowledge subscriptions they can deliver, and a template may match it later.
function resource_subscription_legacy(
    ctx::ServerContext,
    id,
    params;
    session::Union{Nothing,MCPSession}=nothing,
    subscribe::Bool)

    uri = get(params, "uri", nothing)
    if !(uri isa AbstractString) || isempty(uri)
        return error_body(id, MCP_INVALID_PARAMS, "Missing resource URI"), 200
    end
    set_legacy_subscribed(ctx, session, String(uri); subscribed=subscribe)
    return result_response(ctx, id, Dict{String,Any}())
end

subscribe_resource_legacy(
    ctx::ServerContext,
    id,
    params;
    session::Union{Nothing,MCPSession}=nothing) =
    resource_subscription_legacy(ctx, id, params; session=session, subscribe=true)

unsubscribe_resource_legacy(
    ctx::ServerContext,
    id,
    params;
    session::Union{Nothing,MCPSession}=nothing) =
    resource_subscription_legacy(ctx, id, params; session=session, subscribe=false)
