# stdio transport: newline-delimited JSON-RPC and notification forwarding.
# Included into `MCP.Transports` by `../transports.jl`.

"""
    StdioNotifier

Owns a stdio transport's output stream: a write lock serializing every
response and notification onto the one shared channel, the forwarding tasks
(one per listen stream plus the legacy sink), and the broker subscriptions to
close on shutdown.
"""
mutable struct StdioNotifier
    output :: IO
    lock   :: ReentrantLock
    tasks  :: Vector{Task}
    subs   :: Vector{PubSub.Subscription}
end

StdioNotifier(output::IO) = StdioNotifier(output, ReentrantLock(), Task[], PubSub.Subscription[])

"""
    stdio_loop(ctx::ServerContext; input=stdin, output=stdout)

stdio transport entry point. Reads newline-delimited JSON-RPC messages from
`input`, dispatches them, and writes responses to `output`. Notifications
produce no output. The loop returns when `input` reaches end-of-file, which is
the standard graceful-shutdown signal for stdio MCP servers; on the way out all
listen streams are closed gracefully and the notifier's tasks drained.
"""
function stdio_loop(ctx::ServerContext; input::IO=stdin, output::IO=stdout)
    notifier = StdioNotifier(output)
    subscribe_legacy_stdio!(ctx, notifier)

    try
        for line in eachline(input)
            message = strip(line)
            if isempty(message)
                continue
            end

            payload = try
                JSON.parse(message)
            catch
                respond(notifier, error_body(nothing, MCP_PARSE_ERROR, "Parse error"))
                continue
            end

            body = try
                if payload isa AbstractVector
                    first(process_batch(ctx, payload, nothing))
                else
                    first(process(ctx, payload, nothing))
                end
            catch
                error_body(nothing, MCP_INTERNAL_ERROR, "Internal error")
            end

            if isnothing(body)
                continue
            end
            if body isa StreamedCall
                stream_stdio_call(ctx, notifier, body)
            elseif body isa ListenCall
                forward_listen_call(ctx, notifier, body)
            else
                respond(notifier, body)
            end
        end
    finally
        close_listens!(ctx)
        close_notifier!(notifier)
    end
    return nothing
end

# The legacy stdio sink: one broker subscription forwarding resource updates
# for subscribed URIs and capability-gated list changes as plain newline JSON.
# Gated at delivery on a completed handshake by `legacy_event_wanted`.
function subscribe_legacy_stdio!(ctx::ServerContext, notifier::StdioNotifier)
    sub = try
        subscribe_legacy!(ctx; label="legacy-stdio")
    catch error
        if !(error isa PubSub.CapacityError)
            rethrow()
        end
        @warn "stdio legacy notification sink disabled: subscription capacity exhausted"
        return nothing
    end
    push!(notifier.subs, sub)

    source = EventStream(sub.queue, nothing)
    task = @async pump_stream(source,
        event -> begin
            if !(event isa SubscriptionNotification)
                return true
            end
            respond(notifier, notification(event.method, event.params))
            return true
        end)
    push!(notifier.tasks, task)
    return sub
end

# One forwarding task per listen stream: serialized JSON lines, each tagged
# with the subscription id, ending with the JSON-RPC response on `FinalEvent`
# (or an error response on `ErrorEvent`). The record is removed when the task
# exits, whatever the reason.
function forward_listen_call(ctx::ServerContext, notifier::StdioNotifier, call::ListenCall)
    # Finished forwarding tasks are never waited on again, so drop them here
    # instead of letting a long-lived session accumulate one dead task per
    # closed listen stream.
    filter!(task -> !istaskdone(task), notifier.tasks)
    push!(notifier.tasks, @async begin
        try
            pump_stream(call.stream,
                event -> begin
                    body, terminal = listen_frame(call, event)
                    respond(notifier, body)
                    return !terminal
                end)
        finally
            remove_listen!(ctx, call.record)
        end
    end)
    return nothing
end

# End the notifier's subscriptions (releasing the forwarding tasks blocked in
# `take!`) and wait for them to drain their remaining frames.
function close_notifier!(notifier::StdioNotifier)
    for sub in notifier.subs
        close(sub)
    end
    empty!(notifier.subs)

    for task in notifier.tasks
        if task === current_task()
            continue
        end
        try
            wait(task)
        catch
            # A forwarding task may have failed; shutdown still proceeds.
        end
    end
    empty!(notifier.tasks)
    return nothing
end

"""
    stream_stdio_call(ctx, notifier, call::StreamedCall)

Consume one streamed call on stdio. There is no Accept/JSON decision here:
progress notifications are written as newline-delimited JSON-RPC messages as
they arrive, interleaving with the eventual response on the same output stream
(that is how stdio clients correlate them via the token). A request without a
token drains the channel and drops notifications.
"""
function stream_stdio_call(ctx::ServerContext, notifier::StdioNotifier, call::StreamedCall)
    pump_stream(call.stream,
        event -> begin
            body, terminal = streamed_frame(ctx, call, event)
            if !isnothing(body)
                respond(notifier, body)
            end
            return !terminal
        end)

    # A closed channel without a terminal event means the producer was
    # cancelled; make sure nothing is left blocked on it.
    cancel_stream!(call.stream)
    return nothing
end

# All stdio writes go through here (and only here), under the notifier lock, so
# interleaved responses and notifications stay line-atomic.
function respond(notifier::StdioNotifier, body)
    lock(notifier.lock) do
        respond(notifier.output, body)
    end
    return nothing
end

function respond(output::IO, body)
    JSON.print(output, body)
    write(output, '\n')
    flush(output)
    return nothing
end
