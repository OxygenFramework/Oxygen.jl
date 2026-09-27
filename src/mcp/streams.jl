# Channel-based streaming for MCP tool calls: the event model, the
# request-scoped stream handle, the producer task, and the wire mapping from
# events to JSON-RPC notifications.
#
# The engine is one bounded `Channel{StreamEvent}` plus one producer task per
# streamed call. The connection task (HTTP) or the stdio loop owns the consumer
# side and decides, on the first event, whether the reply stays JSON or
# upgrades to an SSE stream. State is per request: nothing here is global.
#
# Included into the `MCP` module by `../mcp.jl`, before `tools.jl` (which
# creates streams) and before `prompts.jl` (which never does).

# ----------------------------------------------------------------------------
# Events
# ----------------------------------------------------------------------------

# The normalized form of everything a handler emits. `progress` is the public
# constructor for the notification-shaped variant; plain yields are classified
# into these types by `normalize_event` on the way into the channel.
abstract type StreamEvent end

struct ProgressEvent <: StreamEvent
    progress :: Float64
    total    :: Union{Nothing,Float64}
    message  :: Union{Nothing,String}
end

# Reserved for the deferred partial-content mappings (FastMCP's
# `notifications/tool/streamContent`, SEP-2998's `notifications/tools/partial_result`).
# No default normalization produces it; `serialize_event` keeps the row so
# landing a mapping later is additive.
struct ContentEvent <: StreamEvent
    block :: Dict{String,Any}
end

struct FinalEvent <: StreamEvent
    value :: Any
end

struct ErrorEvent <: StreamEvent
    error :: Any
end

# Raised by `emit`/`put!`/`check_cancelled` once a client disconnect (or an
# explicit close) has cancelled the request, so long cooperative loops unwind
# instead of blocking on a channel nobody will drain.
struct MCPCancelled <: Exception
    message :: String
end

MCPCancelled() = MCPCancelled("MCP stream was cancelled")

Base.showerror(io::IO, error::MCPCancelled) = print(io, error.message)

# Default per-request event buffer. Bounded on purpose: a slow client
# backpressures the producer instead of buffering without limit.
const STREAM_BUFFER_SIZE = 64

# The connection-side consumer polls at this cadence while the stream is idle,
# so a producer that wakes between frames is forwarded promptly while
# keepalives are only written once the stream has been quiet for the full
# keepalive interval.
const STREAM_POLL_SECONDS = 0.05

# ----------------------------------------------------------------------------
# Public event constructor
# ----------------------------------------------------------------------------

"""
    progress(current, total=nothing; message=nothing)

Build an explicit progress event for `put!`/`emit`. `current` must be
strictly increasing across the request's progress events (auto-incremented
yields do that for you when left implicit). `total` and `message` are optional.
"""
function progress(current::Real, total::Union{Nothing,Real}=nothing; message=nothing)
    return ProgressEvent(
        Float64(current),
        isnothing(total) ? nothing : Float64(total),
        isnothing(message) ? nothing : string(message),
    )
end

# ----------------------------------------------------------------------------
# The stream handle
# ----------------------------------------------------------------------------

"""
    MCPStream

The per-request stream handle. It subclasses `AbstractChannel` so the tool
call path can recognize "this handler returned a stream" with one `isa` check,
but it carries more than a channel:

- `token` is copied from the request when the framework adopts the stream;
- `managed` marks a framework-created handle (Surface A, the injected `; stream`
  argument). Such a handle knows up front whether the client opted in, so
  `emit` is a no-op without a token; a user-created `mcp_stream` handle always
  enqueues because the request context arrives moments after the producer
  starts;
- `cancel` is the cooperative cancellation flag;
- `sequence` is the per-request progress counter (never global), protected by
  `lock` together with the channel put so concurrent emitters cannot reorder
  progress values.
"""
mutable struct MCPStream <: AbstractChannel{StreamEvent}
    channel  :: Channel{StreamEvent}
    token    :: Any                  # request progressToken (nothing when absent)
    managed  :: Bool                 # framework-created (Surface A) handle
    cancel   :: Threads.Atomic{Bool}
    sequence :: Float64              # last progress value emitted for this request
    lock     :: ReentrantLock
end

function MCPStream(csize::Integer=STREAM_BUFFER_SIZE; token=nothing, managed::Bool=false)
    return MCPStream(Channel{StreamEvent}(csize), token, managed,
                     Threads.Atomic{Bool}(false), 0.0, ReentrantLock())
end

# `AbstractChannel` passthroughs. `put!` is deliberately redefined below,
# because every value goes through event normalization on the way in.
Base.eltype(::Type{MCPStream}) = StreamEvent
Base.IteratorSize(::Type{MCPStream}) = Base.SizeUnknown()
Base.isopen(stream::MCPStream) = isopen(stream.channel)
Base.isready(stream::MCPStream) = isready(stream.channel)
Base.take!(stream::MCPStream) = take!(stream.channel)
Base.close(stream::MCPStream) = close(stream.channel)
Base.wait(stream::MCPStream) = wait(stream.channel)
Base.fetch(stream::MCPStream) = fetch(stream.channel)
Base.bind(stream::MCPStream, task::Task) = (bind(stream.channel, task); stream)
Base.iterate(stream::MCPStream, state...) = iterate(stream.channel, state...)

# ----------------------------------------------------------------------------
# Producer side
# ----------------------------------------------------------------------------

"""
    mcp_stream(f; csize=64)

Run `f(stream)` in a producer task and return the `MCPStream` for the
framework to route. Inside `f`, publish notifications with
`put!(stream, value)`/`emit(stream, value)` and return the final tool result;
the return value becomes the terminating `FinalEvent` and a thrown error
becomes an `ErrorEvent`. The channel is closed when `f` finishes either way.

The call is streamed only when the client opted in with a progress token and
accepts the transport's notification channel; a quiet call still returns the
same JSON bytes as a buffered one.
"""
function mcp_stream(f::Function; csize::Integer=STREAM_BUFFER_SIZE)
    stream = MCPStream(csize)
    start_stream!(stream, f)
    return stream
end

# Attach a producer to an existing handle. The framework uses this for Surface
# A (injected `; stream`), where the handle is created with its request context
# already known.
function start_stream!(stream::MCPStream, f::Function)
    @async produce_stream(stream, f)
    return stream
end

function produce_stream(stream::MCPStream, f::Function)
    try
        value = f(stream)
        put!(stream.channel, FinalEvent(value))
    catch error
        # When the consumer stopped listening (client disconnect, explicit
        # cancellation), it closed the channel and a blocked `put!` raised
        # InvalidStateException; that is the intended way for user code to
        # unwind, so it is suppressed rather than reported. Any other failure
        # becomes an error result.
        if !stream.cancel[] && isopen(stream.channel)
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

# Adopt the stream a handler returned. An `mcp_stream` handle only needs its
# request token attached; a raw `AbstractChannel` is consumed on a helper
# task, normalizing each value and appending an empty final result when it
# closes (raw channels have no return value to carry).
function adopt_stream(stream::MCPStream, token)
    stream.token = token
    stream.managed = true
    return stream
end

function adopt_stream(channel::AbstractChannel, token)
    stream = MCPStream(STREAM_BUFFER_SIZE; token=token, managed=true)
    @async begin
        try
            for value in channel
                enqueue!(stream, value)
            end
            put!(stream.channel, FinalEvent(nothing))
        catch error
            if !stream.cancel[] && isopen(stream.channel)
                try
                    put!(stream.channel, ErrorEvent(error))
                catch
                end
            end
        finally
            close(stream.channel)
        end
    end
    return stream
end

"""
    emit(stream, value)

Publish one event on a stream. Handlers may call this unconditionally: a
framework-created handle without a progress token drops the value, and the
transport filters anything the client did not opt into. Once the request has
been cancelled (client gone), emitting throws `MCPCancelled` so the handler
unwinds.
"""
function emit(stream::MCPStream, value)
    check_cancelled(stream)
    stream.managed && stream.token === nothing && return nothing
    enqueue!(stream, value)
    return nothing
end

# `put!` is the Surface B spelling of `emit`; it keeps working on a handle
# whose request context has not been attached yet, which is why it normalizes
# and enqueues even without a token (the consumer drops unopted notifications).
function Base.put!(stream::MCPStream, value)
    check_cancelled(stream)
    enqueue!(stream, value)
    return stream
end

# Normalize and enqueue under the handle lock: the lock is held across the
# blocking `put!` so progress values are assigned and written in the same
# order even with concurrent emitters. The consumer never takes this lock, so
# a full buffer blocks the producer (backpressure) without deadlocking.
function enqueue!(stream::MCPStream, value)
    lock(stream.lock)
    try
        put!(stream.channel, normalize_event(stream, value))
    finally
        unlock(stream.lock)
    end
    return nothing
end

"""
    check_cancelled(stream)

Throw `MCPCancelled` if the request has been cancelled. Long cooperative loops
that do not emit often can call this between steps to stop promptly.
"""
check_cancelled(stream::MCPStream) = stream.cancel[] ? throw(MCPCancelled()) : nothing

# What the connection task calls when it detects a dead peer (or when a
# streamed call finishes and any child producers must stop). Setting the flag
# makes future `emit`s throw; closing the channel releases a producer blocked
# on `put!` with an InvalidStateException, which `produce_stream` suppresses.
function cancel_stream!(stream::MCPStream)
    stream.cancel[] = true
    isopen(stream.channel) && close(stream.channel)
    return nothing
end

# ----------------------------------------------------------------------------
# Yield classification (design §5.1)
# ----------------------------------------------------------------------------

# Normalize a yielded value into an event. Auto-numbered progress starts at 1
# and is monotonic across mixed yields; explicit values must strictly increase.
function normalize_event(stream::MCPStream, event::ProgressEvent)
    record_progress!(stream, event.progress)
    return event
end

normalize_event(::MCPStream, event::StreamEvent) = event

function normalize_event(stream::MCPStream, value::AbstractString)
    return ProgressEvent(next_progress!(stream), nothing, String(value))
end

function normalize_event(stream::MCPStream, value::Real)
    return ProgressEvent(record_progress!(stream, Float64(value)), nothing, nothing)
end

function normalize_event(stream::MCPStream, ::Nothing)
    return ProgressEvent(next_progress!(stream), nothing, nothing)
end

function normalize_event(stream::MCPStream, value)
    return ProgressEvent(next_progress!(stream), nothing, JSON.json(value))
end

# The auto counter always lands on the next integer above the last value, so a
# string yield after an explicit `progress(2.5)` is 3 and never repeats.
function next_progress!(stream::MCPStream)::Float64
    stream.sequence = floor(stream.sequence) + 1
    return stream.sequence
end

# Explicit values must strictly increase (the spec requires monotonic
# progress); a smaller or repeated value is an authoring bug.
function record_progress!(stream::MCPStream, value::Real)::Float64
    current = Float64(value)
    current > stream.sequence ||
        throw(ArgumentError("progress must increase monotonically (got $current after $(stream.sequence))"))
    stream.sequence = current
    return current
end

# ----------------------------------------------------------------------------
# Wire mapping
# ----------------------------------------------------------------------------

function notification(method::String, params::Dict{String,Any})::Dict{String,Any}
    return Dict{String,Any}("jsonrpc" => "2.0", "method" => method, "params" => params)
end

"""
    serialize_event(token, event) :: Union{Nothing,Dict}

Map one event to the JSON-RPC notification that carries it on the wire, or
`nothing` when the request did not opt into it (no progress token). This is
the single seam for wire mappings: extensions add a method (a table row), they
do not refactor the router.
"""
function serialize_event(token, event::ProgressEvent)
    token === nothing && return nothing
    params = Dict{String,Any}("progressToken" => token, "progress" => event.progress)
    event.total === nothing || (params["total"] = event.total)
    event.message === nothing || (params["message"] = event.message)
    return notification("notifications/progress", params)
end

# No default mapping for partial content yet (see `ContentEvent`); this method
# is where the gate lands when the mapping is enabled.
function serialize_event(token, event::ContentEvent)
    return nothing
end

# ----------------------------------------------------------------------------
# Terminal result serialization
# ----------------------------------------------------------------------------

# Everything the connection task needs to turn terminal events into the exact
# JSON-RPC body the buffered `tools/call` path would have produced.
struct StreamedCall
    stream  :: MCPStream
    id      :: Any
    modern  :: Bool
    version :: String
end

function streamed_body(ctx::ServerContext, call::StreamedCall, event::FinalEvent)::Dict{String,Any}
    result = toolresult(event.value)
    if !call.modern && !supports_structured_content(call.version)
        strip_unstructured!(result)
    end
    call.modern && (result = modern_envelope(ctx, result))
    return result_body(call.id, result)
end

function streamed_body(ctx::ServerContext, call::StreamedCall, event::ErrorEvent)::Dict{String,Any}
    result = toolerror_result(event.error)
    call.modern && (result = modern_envelope(ctx, result))
    return result_body(call.id, result)
end

# A drain can end without a terminal event (only possible after cancellation or
# a producer bug). Be explicit rather than writing a half response.
function streamed_body(ctx::ServerContext, call::StreamedCall, ::Nothing)::Dict{String,Any}
    return streamed_body(ctx, call, ErrorEvent(ErrorException("tool stream ended without a result")))
end
