# MCP-specific streaming policy: the progress event model, the request-scoped
# state, and the wire mapping from events to JSON-RPC notifications. The
# protocol-free engine (bounded channel, producer task, backpressure,
# cancellation, consumer pump) lives in `../streaming.jl`; this file layers MCP
# on top of it.
#
# Included into the `MCP` module by `../mcp.jl`, before `tools.jl` (which
# creates streams) and before `prompts.jl` (which never does).

# ----------------------------------------------------------------------------
# Events
# ----------------------------------------------------------------------------

# The normalized form of everything an MCP handler emits. `progress` is the
# public constructor for the notification-shaped variant; plain yields are
# classified into these types by `normalize_event` on the way into the channel.
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

# Kept for backwards compatibility with the pre-generic engine name.
const MCPCancelled = StreamCancelled

# The per-request MCP state attached to the generic stream handle:
# - `token` is copied from the request when the framework adopts the stream;
# - `managed` marks a framework-created handle (Surface A, the injected
#   `; stream` argument). Such a handle knows up front whether the client
#   opted in, so `emit` is a no-op without a token; a user-created
#   `mcp_stream` handle always enqueues because the request context arrives
#   moments after the producer starts;
# - `sequence` is the per-request progress counter (never global), protected
#   by the handle lock together with the channel put so concurrent emitters
#   cannot reorder progress values.
mutable struct MCPState
    token    :: Any                  # request progressToken (nothing when absent)
    managed  :: Bool                 # framework-created (Surface A) handle
    sequence :: Float64              # last progress value emitted for this request
end

# `MCPStream` is the generic engine specialized to MCP's event type and
# policy state. Keeping it as an alias preserves the existing name and the
# `isa AbstractChannel` recognition used by the tool call path.
const MCPStream = EventStream{StreamEvent, MCPState}

function MCPStream(csize::Integer=STREAM_BUFFER_SIZE; token=nothing, managed::Bool=false)
    return EventStream(Channel{StreamEvent}(csize), MCPState(token, managed, 0.0))
end

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

# Adopt the stream a handler returned. An `mcp_stream` handle only needs its
# request token attached; a raw `AbstractChannel` is consumed on a helper
# task, normalizing each value and appending an empty final result when it
# closes (raw channels have no return value to carry).
function adopt_stream(stream::MCPStream, token)
    stream.protocol.token = token
    stream.protocol.managed = true
    return stream
end

function adopt_stream(channel::AbstractChannel, token)
    stream = MCPStream(STREAM_BUFFER_SIZE; token=token, managed=true)
    # Raw channels have no return value to carry, so an exhausted channel ends
    # the stream with an empty result. This is exactly `produce_stream`'s
    # producer contract; reuse it instead of duplicating the error handling.
    start_stream!(stream, _ -> begin
        for value in channel
            enqueue!(stream, value)
        end
        return nothing
    end)
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
    state = stream.protocol
    state.managed && state.token === nothing && return nothing
    enqueue!(stream, value)
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
    stream.protocol.sequence = floor(stream.protocol.sequence) + 1
    return stream.protocol.sequence
end

# Explicit values must strictly increase (the spec requires monotonic
# progress); a smaller or repeated value is an authoring bug.
function record_progress!(stream::MCPStream, value::Real)::Float64
    current = Float64(value)
    current > stream.protocol.sequence ||
        throw(ArgumentError("progress must increase monotonically (got $current after $(stream.protocol.sequence))"))
    stream.protocol.sequence = current
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
# JSON-RPC body the buffered `tools/call` path would have produced, shaped by
# the request's protocol revision (`spec`).
struct StreamedCall
    stream :: MCPStream
    id     :: Any
    spec   :: Val
end

function streamed_body(ctx::ServerContext, call::StreamedCall, event::FinalEvent)::Dict{String,Any}
    result = tool_success_result(event.value; spec=call.spec)
    return result_body(call.id, result_envelope(call.spec, ctx, result))
end

function streamed_body(ctx::ServerContext, call::StreamedCall, event::ErrorEvent)::Dict{String,Any}
    result = toolerror_result(event.error)
    return result_body(call.id, result_envelope(call.spec, ctx, result))
end

# A drain can end without a terminal event (only possible after cancellation or
# a producer bug). Be explicit rather than writing a half response.
function streamed_body(ctx::ServerContext, call::StreamedCall, ::Nothing)::Dict{String,Any}
    return streamed_body(ctx, call, ErrorEvent(ErrorException("tool stream ended without a result")))
end

"""
    streamed_frame(ctx, call, event) :: (body, terminal)

Map one event of a streamed `tools/call` to the JSON-RPC body a transport should
write — `nothing` when the client did not opt into the notification — and
whether the stream ended.
"""
function streamed_frame(ctx::ServerContext, call::StreamedCall, event)::Tuple{Union{Nothing,Dict{String,Any}},Bool}
    if event isa FinalEvent || event isa ErrorEvent
        return streamed_body(ctx, call, event), true
    end
    return serialize_event(call.stream.protocol.token, event), false
end
