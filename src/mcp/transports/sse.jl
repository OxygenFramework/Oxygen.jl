# SSE consumers for streamed tool calls, listen streams, and legacy notifications.
# Included into `MCP.Transports` by `../transports.jl`.

"""
    stream_call(ctx, stream, req, call::StreamedCall)

Consume one streamed `tools/call`. The first event decides the wire shape:
a terminal event (or a drained channel) stays plain JSON, while a notification
upgrades the response to SSE. On a failed frame write (client disconnect) the
channel is closed, which releases a producer blocked in `put!`.
"""
function stream_call(ctx::ServerContext, stream::HTTP.Stream, req::HTTP.Request, call::StreamedCall)
    token = call.stream.protocol.token

    if isnothing(token) || !accepts_event_stream(req)
        terminal = drain_stream!(call.stream)
        return write_json_response(stream, streamed_body(ctx, call, terminal))
    end

    first = try
        take!(call.stream.channel)
    catch error
        if !(error isa InvalidStateException)
            rethrow()
        end
        # The producer was cancelled before emitting; the client is gone.
        cancel_stream!(call.stream)
        return nothing
    end

    if first isa FinalEvent || first isa ErrorEvent
        cancel_stream!(call.stream)
        return write_json_response(stream, streamed_body(ctx, call, first))
    end

    # Upgrade to SSE. Headers go out before the first frame so proxies see the
    # content type immediately; every frame is flushed for the same reason.
    return stream_sse(stream, call.stream,
        event -> begin
            body, terminal = streamed_frame(ctx, call, event)
            if !isnothing(body)
                write_sse_frame(stream, body)
            end
            return !terminal
        end;
        initial = first,
        cleanup = () -> cancel_stream!(call.stream))
end

"""
    stream_listen_call(ctx, stream, req, call::ListenCall)

Consume one modern `subscriptions/listen` stream. The response is SSE-only: a
request without an `Accept: text/event-stream` range is rejected with a JSON-RPC
error and the stream is torn down. The first frame is always the acknowledgement
(enqueued by `listen_call` before registration), every frame carries the
subscription id under `params._meta`, and a `FinalEvent` is written as the
JSON-RPC response that closes the stream gracefully. On disconnect the stream is
cancelled (which prunes the broker subscription) and the record removed.
"""
function stream_listen_call(ctx::ServerContext, stream::HTTP.Stream, req::HTTP.Request, call::ListenCall)
    if !accepts_event_stream(req)
        remove_listen!(ctx, call.record)
        cancel_stream!(call.stream)
        return write_json_response(stream,
            error_body(call.id, MCP_INVALID_REQUEST,
                       "subscriptions/listen requires Accept: text/event-stream");
            status=400)
    end

    return stream_sse(stream, call.stream,
        event -> begin
            body, terminal = listen_frame(call, event)
            write_sse_frame(stream, body)
            return !terminal
        end;
        cleanup = () -> begin
            cancel_stream!(call.stream)
            remove_listen!(ctx, call.record)
        end)
end

"""
    stream_notifications(ctx, stream::HTTP.Stream)

Hold the legacy server→client notification channel open as an SSE stream: a
broker subscription forwards `notifications/resources/updated` for the
connection's `resources/subscribe` set and capability-gated `list_changed`
notifications, interleaved with periodic keep-alive comments. A session-scoped
sink reads the session's own set and the stream is closed when that session is
terminated with `DELETE`; a header-less sink keeps using the anonymous set. It
stays open until the client disconnects. This is what stops mainstream clients
from tearing the stream down and reconnecting once per second.
"""
function stream_notifications(ctx::ServerContext, stream::HTTP.Stream;
                              session::Union{Nothing,MCPSession}=nothing)
    mcp_broker = broker(ctx)
    sub = try
        subscribe_legacy!(ctx; label="legacy-http", session=session)
    catch error
        if !(error isa PubSub.CapacityError)
            rethrow()
        end
        return write_stream_response(stream, 503, "text/plain; charset=utf-8",
                                     "Notification capacity exhausted")
    end
    if isnothing(sub)
        return write_stream_response(stream, 404, "application/json; charset=utf-8",
                                     JSON.json(error_body(nothing, MCP_INVALID_REQUEST,
                                                          "Unknown or expired session")))
    end

    return stream_sse(stream, EventStream(sub.queue, nothing),
        event -> begin
            if !(event isa SubscriptionNotification)
                return true
            end
            write_sse_frame(stream, notification(event.method, event.params))
            return true
        end;
        on_open = () -> begin
            # Priming comment: lets the client see the stream is live immediately.
            write(stream, ": connected\n\n")
            flush(stream)
        end,
        connection_header = "keep-alive",
        cleanup = () -> begin
            PubSub.unsubscribe!(mcp_broker, sub)
            if session isa MCPSession
                remove_sink!(session, sub)
            end
        end)
end
