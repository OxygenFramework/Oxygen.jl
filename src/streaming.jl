# Generic channel-based streaming.
#
# This module owns the protocol-free engine: a bounded event channel, a
# producer task per stream, cancellation, backpressure/ordering, the consumer
# pump, and one concrete protocol adapter (server-sent events). Protocol
# adapters layer their own event model and wire mapping on top by choosing an
# event type and implementing `normalize_event`; MCP does exactly that in
# `mcp/streams.jl`.
#
# The engine is one `EventStream{T,P}` per request: `T` is the event type and
# `P` is wrapper-owned protocol state. Nothing here is global.

module Streaming

using HTTP
using JSON

import ..Util: format_response, format_sse_message

export StreamEvent, DataEvent, FinalEvent, ErrorEvent, StreamCancelled,
    EventStream, stream_events, adopt_channel, emit, pump_stream, drain_stream!,
    cancel_stream!, check_cancelled, sse_stream, SSEEvent, stream_sse,
    STREAM_BUFFER_SIZE, STREAM_POLL_SECONDS, SSE_KEEPALIVE_SECONDS

# ----------------------------------------------------------------------------
# Events
# ----------------------------------------------------------------------------

# The root event type. Protocol adapters subtype it for their own events and
# use the terminal envelopes below to end a stream.
abstract type StreamEvent end

# A protocol-neutral payload event. The default normalization wraps every
# yielded value in one of these, so consumers (e.g. the SSE adapter) can
# serialize arbitrary objects without knowing the producer's intentions.
struct DataEvent <: StreamEvent
    value :: Any
end

# Terminal events: the producer's return value and a raised error. They bypass
# normalization and are interpreted by the protocol consumer (MCP turns them
# into a JSON-RPC result; the SSE adapter closes the stream).
struct FinalEvent <: StreamEvent
    value :: Any
end

struct ErrorEvent <: StreamEvent
    error :: Any
end

# Raised by `emit`/`put!`/`check_cancelled` once a client disconnect (or an
# explicit close) has cancelled the request, so long cooperative loops unwind
# instead of blocking on a channel nobody will drain.
struct StreamCancelled <: Exception
    message :: String
end

StreamCancelled() = StreamCancelled("stream was cancelled")

Base.showerror(io::IO, error::StreamCancelled) = print(io, error.message)

# Default per-request event buffer. Bounded on purpose: a slow client
# backpressures the producer instead of buffering without limit.
const STREAM_BUFFER_SIZE = 64

# The connection-side consumer polls at this cadence while the stream is idle,
# so a producer that wakes between frames is forwarded promptly while
# keepalives are only written once the stream has been quiet for the full
# keepalive interval.
const STREAM_POLL_SECONDS = 0.05

# Interval between keep-alive comments on an idle SSE stream.
const SSE_KEEPALIVE_SECONDS = 3

# ----------------------------------------------------------------------------
# The stream handle
# ----------------------------------------------------------------------------

"""
    EventStream{T,P}

The per-request stream handle, shared by every protocol: `T` is the event type
the consumer sees and `P` is mutable, wrapper-owned protocol state (MCP stores
its progress token and counter there; the SSE adapter needs none).

It subclasses `AbstractChannel{T}` so a handler result can be recognized with
one `isa AbstractChannel` check, while `channel`, `cancel`, `lock` and `source`
carry the engine mechanics:

- `cancel` is the cooperative cancellation flag;
- `lock` is held across the blocking channel `put!`, which both serializes
  concurrent emitters (in order) and applies backpressure;
- `source` is the caller-owned channel this stream was adopted from (see
  `adopt_channel`), closed on cancellation so the caller's producer unwinds.
"""
mutable struct EventStream{T,P} <: AbstractChannel{T}
    channel  :: Channel{T}
    protocol :: P
    cancel   :: Threads.Atomic{Bool}
    lock     :: ReentrantLock
    source   :: Union{Nothing,AbstractChannel}
end

function EventStream(channel::Channel{T}, protocol::P,
                     source::Union{Nothing,AbstractChannel}=nothing) where {T,P}
    return EventStream{T,P}(channel, protocol, Threads.Atomic{Bool}(false), ReentrantLock(), source)
end

# Readable REPL display: lifecycle state and queued depth instead of the raw
# struct fields. `cancelled` distinguishes an explicit close (or client
# disconnect) from a producer that finished normally.
function Base.show(io::IO, stream::EventStream{T}) where {T}
    state = stream.cancel[] ? "cancelled" : isopen(stream) ? "open" : "closed"
    print(io, "EventStream{", T, "}(", state, ", ", Base.n_avail(stream), " buffered)")
end

# `AbstractChannel` passthroughs. `put!` is deliberately redefined below,
# because every value goes through event normalization on the way in.
Base.eltype(::Type{<:EventStream{T}}) where {T} = T
Base.IteratorSize(::Type{<:EventStream}) = Base.SizeUnknown()

# The state read is taken under the channel lock so it cannot race with `close`.
function Base.isopen(stream::EventStream)::Bool
    lock(stream.channel)
    try
        return isopen(stream.channel)
    finally
        unlock(stream.channel)
    end
end

Base.isready(stream::EventStream) = isready(stream.channel)
Base.take!(stream::EventStream) = take!(stream.channel)

# Buffer-state queries, forwarded so generic channel code sees the same answers
# as for the wrapped `Channel`. `n_avail` also reports buffered items after the
# channel closes, which stay drainable.
Base.isbuffered(stream::EventStream) = Base.isbuffered(stream.channel)
Base.n_avail(stream::EventStream) = Base.n_avail(stream.channel)

# `Base.isfull` exists on Julia >= 1.12; on older runtimes the block is skipped
# rather than creating the Base binding ourselves.
if isdefined(Base, :isfull)
    Base.isfull(stream::EventStream) = Base.isfull(stream.channel)
end

# Closing the handle is cancellation: producers blocked in `put!` unwind with
# `StreamCancelled` and later emits do not touch a closed channel. A producer
# finishing normally closes the raw channel in its `finally`, which does not
# mark cancellation.
function Base.close(stream::EventStream)
    cancel_stream!(stream)
    return nothing
end
Base.wait(stream::EventStream) = wait(stream.channel)
Base.fetch(stream::EventStream) = fetch(stream.channel)
Base.bind(stream::EventStream, task::Task) = (bind(stream.channel, task); stream)
Base.iterate(stream::EventStream, state...) = iterate(stream.channel, state...)

# ----------------------------------------------------------------------------
# Producer side
# ----------------------------------------------------------------------------

"""
    stream_events(f, protocol; csize=STREAM_BUFFER_SIZE)

Run `f(stream)` in a producer task and return the resulting `EventStream`.
This is the parent function every protocol wrapper builds on:

- values published with `put!(stream, value)`/`emit(stream, value)` pass
  through `normalize_event` (protocol hook) before entering the channel;
- the value `f` returns becomes the terminating `FinalEvent` and a thrown error
  becomes an `ErrorEvent`;
- the channel is closed when `f` finishes either way.

`protocol` is arbitrary mutable state owned by the wrapper; the generic engine
never inspects it.
"""
function stream_events(f::Function, protocol; csize::Integer=STREAM_BUFFER_SIZE)
    stream = EventStream(Channel{StreamEvent}(csize), protocol)
    start_stream!(stream, f)
    return stream
end

# Attach a producer to an existing handle. Wrappers that need request context
# in the handle up front (MCP's injected `; stream`) use this directly.
function start_stream!(stream::EventStream, f::Function)
    @async produce_stream(stream, f)
    return stream
end

function produce_stream(stream::EventStream, f::Function)
    try
        value = f(stream)
        put!(stream.channel, FinalEvent(value))
    catch error
        # When the consumer stopped listening (client disconnect, explicit
        # cancellation), it closed the channel and a blocked `put!` raised
        # InvalidStateException; that is the intended way for user code to
        # unwind, so it is suppressed rather than reported. Any other failure
        # becomes an error result; a put into an already-closed channel is
        # likewise dropped.
        if !stream.cancel[]
            try
                put!(stream.channel, ErrorEvent(error))
            catch
            end
        end
    finally
        close(stream.channel)
    end
    return nothing
end

# ----------------------------------------------------------------------------
# Channel adoption
# ----------------------------------------------------------------------------

"""
    adopt_channel(channel, protocol; csize=STREAM_BUFFER_SIZE) :: EventStream

Adopt a caller-owned `channel` as an `EventStream`: every value it yields is
normalized into the adopted stream, while a `FinalEvent` (the marker built by
`result`) ends the stream. The marker is intercepted as the producer's return
value instead of an event, and the framework closes `channel`, so it must be
written last; later writes fail. The returned handle terminates with exactly
one `FinalEvent` carrying that value (`nothing` when the channel produced no
marker). A failure of the channel's producer is reported with the original
exception (task failures are unwrapped), and the source is recorded so
cancellation closes it, releasing a producer blocked in `put!`.

`protocol` is the wrapper-owned state the handle carries, exactly as in
`stream_events`.
"""
function adopt_channel(channel::AbstractChannel, protocol::P;
                       csize::Integer=STREAM_BUFFER_SIZE) where {P}
    stream = EventStream(Channel{StreamEvent}(csize), protocol, channel)
    start_stream!(stream, _ -> pump_channel(stream, channel))
    return stream
end

# The adoption pump: forward every value of the adopted channel, interpreting a
# `FinalEvent` as the producer's return value instead of an event (the marker
# therefore never reaches the adopted stream). The first marker ends the
# stream: the pump closes the source channel, so the writer does not have to,
# and nothing written after it is consumed. A task-bound source whose producer
# failed surfaces as `TaskFailedException`; unwrap it so the consumer sees the
# real error.
function pump_channel(stream::EventStream, channel::AbstractChannel)
    value = nothing
    try
        while true
            # Take rather than iterate: `iterate` swallows a failed producer on
            # Julia < 1.12, while `take!` rethrows it on every version.
            item = try
                take!(channel)
            catch error
                error isa InvalidStateException && break
                rethrow()
            end
            if item isa FinalEvent
                value = item.value
                close_source!(stream)
                break
            end
            enqueue!(stream, item)
        end
    catch error
        if error isa TaskFailedException
            throw(error.task.exception)
        end
        rethrow()
    end
    return value
end

function Base.put!(stream::EventStream, value)
    check_cancelled(stream)
    enqueue!(stream, value)
    return stream
end

"""
    emit(stream, value)

Publish one event on a stream. This is the protocol-neutral spelling of
`put!`; protocol wrappers may override it with their own gating rules (MCP
drops values when the client did not opt in).
"""
function emit(stream::EventStream, value)
    put!(stream, value)
    return nothing
end

# Normalize and enqueue under the handle lock: the lock is held across the
# blocking `put!` so events are assigned and written in the same order even
# with concurrent emitters. The consumer never takes this lock, so a full
# buffer blocks the producer (backpressure) without deadlocking.
function enqueue!(stream::EventStream, value)
    lock(stream.lock)
    try
        # Re-check under the lock so a cancellation racing the caller's
        # `check_cancelled` cannot enqueue into a closing stream.
        if stream.cancel[]
            throw(StreamCancelled())
        end
        event = normalize_event(stream, value)
        if !isnothing(event)
            try
                put!(stream.channel, event)
            catch error
                # `cancel_stream!` closes the channel, releasing a blocked
                # `put!` with an `InvalidStateException`; surface the
                # documented `StreamCancelled` instead.
                if stream.cancel[] && error isa InvalidStateException
                    throw(StreamCancelled())
                end
                rethrow()
            end
        end
    finally
        unlock(stream.lock)
    end
    return nothing
end

# How a yielded value becomes an event. Adapters extend the hook to implement
# their event model; returning `nothing` drops the value. The default wraps
# every value (already-normalized events pass through untouched) so arbitrary
# objects reach the consumer for serialization.
normalize_event(::EventStream, event::StreamEvent) = event
normalize_event(::EventStream, value) = DataEvent(value)

"""
    check_cancelled(stream)

Throw `StreamCancelled` if the request has been cancelled. Long cooperative
loops that do not emit often can call this between steps to stop promptly.
"""
function check_cancelled(stream::EventStream)
    if stream.cancel[]
        throw(StreamCancelled())
    end
    return nothing
end

# What the connection task calls when it detects a dead peer (or when a
# streamed call finishes and any child producers must stop). Setting the flag
# makes future `emit`s throw; closing the channel releases a producer blocked
# on `put!` with an `InvalidStateException`, which `enqueue!` maps back to
# `StreamCancelled`. An adopted source (see `adopt_channel`) is closed too, so
# the caller's producer unwinds and its `finally` runs.
function cancel_stream!(stream::EventStream)
    stream.cancel[] = true
    close(stream.channel)
    close_source!(stream)
    return nothing
end

# Close the caller-owned channel an adopted stream wrapped, if any. Guarded:
# the source may already be closed (closing a channel is only idempotent for
# `Channel`) or owned by an implementation without a working `close`.
function close_source!(stream::EventStream)
    source = stream.source
    if !isnothing(source)
        try
            close(source)
        catch
        end
    end
    return nothing
end

# ----------------------------------------------------------------------------
# Consumer side
# ----------------------------------------------------------------------------

"""
    pump_stream(stream, on_event; on_idle=nothing, poll=STREAM_POLL_SECONDS)

Consume a stream until it is closed (and drained). `on_event(event)` is called
for every event; returning `false` stops the pump (that is how protocol
consumers break on terminal events). When `on_idle` is given the pump polls
instead of blocking so the callback can write keep-alives while the producer is
idle; without it the pump blocks on `take!` and forwards events with no polling
delay.

Write failures inside the callbacks propagate to the caller, which owns
disconnect handling (`cancel_stream!` releases the producer).
"""
function pump_stream(stream::EventStream, on_event::Function;
                     on_idle::Union{Nothing,Function}=nothing,
                     poll::Real=STREAM_POLL_SECONDS)
    if isnothing(on_idle)
        while true
            event = try
                take!(stream.channel)
            catch error
                if error isa InvalidStateException
                    break
                end
                rethrow()
            end
            if on_event(event) === false
                break
            end
        end
    else
        while true
            if !isready(stream)
                if !isopen(stream)
                    break
                end
                on_idle()
                sleep(poll)
                continue
            end
            event = try
                take!(stream.channel)
            catch error
                # The channel can close between `isready` and `take!`; the
                # stream has simply ended.
                if error isa InvalidStateException
                    break
                end
                rethrow()
            end
            if on_event(event) === false
                break
            end
        end
    end
    return nothing
end

# Drain a stream without writing it and return its terminal event. Every event
# is taken so a producer can never block on a full buffer. The first terminal
# wins, matching `pump_stream` (which stops on it); later terminals are taken
# and dropped so a misbehaving producer cannot overwrite the result.
function drain_stream!(stream::EventStream)::Union{Nothing,FinalEvent,ErrorEvent}
    terminal::Union{Nothing,FinalEvent,ErrorEvent} = nothing
    while true
        event = try
            take!(stream.channel)
        catch error
            if error isa InvalidStateException
                break
            end
            rethrow()
        end
        if (event isa FinalEvent || event isa ErrorEvent) && isnothing(terminal)
            terminal = event
        end
    end
    return terminal
end

# ----------------------------------------------------------------------------
# Server-sent events adapter
# ----------------------------------------------------------------------------

"""
    SSEEvent(data; event=nothing, id=nothing, retry=nothing)

An explicit server-sent event yielded into an `sse_stream`. `data` is written
as-is when it is a string, otherwise JSON-encoded; `event`, `id` and `retry`
map to the SSE fields of the same name. Yielding a plain value (not an
`SSEEvent`) writes it as a `data:` frame the same way.
"""
struct SSEEvent
    data  :: Any
    event :: Union{Nothing,String}
    id    :: Union{Nothing,String}
    retry :: Union{Nothing,Int}
end

SSEEvent(data; event=nothing, id=nothing, retry=nothing) =
    SSEEvent(data, event, id, retry)

"""
    sse_stream(f; csize=STREAM_BUFFER_SIZE)

Run `f(stream)` in a producer task and return the `EventStream` for the
framework to route as server-sent events. Inside `f`, publish events with
`put!(stream, value)`/`emit(stream, value)`: every value lands in a `data:`
frame (strings are written as-is, everything else is JSON-encoded), while
`SSEEvent` values control the frame's `event`, `id` and `retry` fields. The
value `f` returns is not streamed; a thrown error ends the stream with an
`event: error` frame.

Return the stream from any handler (`@get`, `@stream`, ...) and Oxygen writes
the SSE response to the connection; requests without a live connection (e.g.
`internalrequest`) buffer the stream and return its final value instead.

A handler may also return a raw `AbstractChannel`: the framework adopts it on
the same terms, streaming its values as frames. A `result(value)` marker ends
the stream and the framework closes the channel; on a live connection the
marker has no frame: closing the connection is the ending, while a caller
without a connection (`internalrequest`, cron, tasks) receives the marker
value as the response body (`null` when the channel had no marker). `SSEEvent`
remains the way to control a frame's `event:`, `id:` and `retry:` fields.
"""
function sse_stream(f::Function; csize::Integer=STREAM_BUFFER_SIZE)
    return stream_events(f, nothing; csize=csize)
end

function sse_frame(event::DataEvent)
    return sse_frame(event.value)
end

function sse_frame(value)
    payload = value isa SSEEvent ? value : SSEEvent(value)
    data = payload.data isa AbstractString ? String(payload.data) : JSON.json(payload.data)
    return format_sse_message(data; event=payload.event, id=payload.id, retry=payload.retry)
end

function write_error_frame(stream::HTTP.Stream, error)
    message = sprint(showerror, error)
    write(stream, format_sse_message(JSON.json(Dict("error" => message)); event="error"))
    return nothing
end

# Write one event to the connection. Returns `false` for terminal events so the
# pump stops; `DataEvent` payloads become frames and `ErrorEvent`s become an
# `event: error` frame. Payloads are serialized lazily here (unlike MCP, which
# serializes on the producer side), so a bad payload is reported as an error
# frame and ends the stream rather than killing the connection silently.
function write_sse_event(stream::HTTP.Stream, event::StreamEvent)
    if event isa ErrorEvent
        write_error_frame(stream, event.error)
        return false
    elseif event isa FinalEvent
        return false
    end
    try
        write(stream, sse_frame(event))
    catch error
        write_error_frame(stream, error)
        return false
    end
    return true
end

function write_sse_response(stream::HTTP.Stream, source::EventStream)
    stream_sse(stream, source,
        event -> begin
            keep = write_sse_event(stream, event)
            flush(stream)
            return keep
        end;
        cleanup = () -> cancel_stream!(source))
    return HTTP.Response(200, "")
end

# Write one keep-alive comment when the connection has been quiet for the full
# interval. Shared by every SSE writer.
function keepalive!(connection::HTTP.Stream, last_write::Ref{Float64})
    now = time()
    if now - last_write[] >= SSE_KEEPALIVE_SECONDS
        write(connection, ": keepalive\n\n")
        flush(connection)
        last_write[] = now
    end
    return nothing
end

"""
    stream_sse(connection, source, write_event; initial=nothing, cleanup=() -> nothing,
               on_open=nothing, connection_header="close")

Low-level SSE response writer shared by the generic adapter and MCP: writes the
SSE headers, optionally calls `on_open` (for a priming comment), writes `initial`
through `write_event`, then pumps `source`, calling `write_event(event) -> Bool`
for every event (returning `false` stops the pump) and writing keep-alive
comments while the producer is idle. `cleanup` runs in the `finally`, before the
write side of the connection is closed; a throwing `cleanup` still closes the
write side, and the error then propagates to the caller.
"""
function stream_sse(connection::HTTP.Stream, source::EventStream, write_event::Function;
                    initial=nothing, cleanup::Function=() -> nothing,
                    on_open::Union{Nothing,Function}=nothing,
                    connection_header::String="close")
    HTTP.setstatus(connection, 200)
    HTTP.setheader(connection, "Content-Type" => "text/event-stream")
    HTTP.setheader(connection, "Cache-Control" => "no-cache")
    HTTP.setheader(connection, "X-Accel-Buffering" => "no")
    HTTP.setheader(connection, "Connection" => connection_header)

    last_write = Ref(time())
    keep = true
    try
        HTTP.startwrite(connection)
        if !isnothing(on_open)
            on_open()
            last_write[] = time()
        end
        if !isnothing(initial)
            keep = write_event(initial) !== false
            if keep
                last_write[] = time()
            end
        end
        if keep
            pump_stream(source,
                event -> begin
                    keep = write_event(event) !== false
                    if keep
                        last_write[] = time()
                    end
                    return keep
                end;
                on_idle = () -> keepalive!(connection, last_write))
        end
    catch
        # A failed write means the client disconnected; end quietly.
    finally
        # The write side must close even when `cleanup` fails, so nest it: a
        # throwing cleanup would otherwise leak the connection.
        try
            cleanup()
        finally
            try
                HTTP.closewrite(connection)
            catch
            end
        end
    end
    return nothing
end

# A regular handler that returns a stream is answered with SSE when there is a
# live connection. Requests without one (internal requests, background tasks)
# drain the stream and return its final value as a normal response.
function format_response(req::HTTP.Request, source::EventStream)
    connection = get(req.context, :stream, nothing)
    if connection isa HTTP.Stream
        return write_sse_response(connection, source)
    end

    terminal = drain_stream!(source)
    if terminal isa ErrorEvent
        throw(terminal.error)
    end
    value = terminal isa FinalEvent ? terminal.value : nothing
    return format_response(req, value)
end

# A handler may also return a raw `AbstractChannel`; the engine adopts it on the
# same terms as MCP (`result` marks the terminal value). A live connection gets
# SSE frames: the marker itself has no frame, and closing the connection is
# the ending, while a request without one (internalrequest, cron, tasks) drains
# the stream and answers with the marker value (or `null` without one). The
# `EventStream` method above stays more specific, so helper-created streams
# keep taking the direct path.
function format_response(req::HTTP.Request, source::AbstractChannel)
    return format_response(req, adopt_channel(source, nothing))
end

end
