module MCP

using HTTP
using JSON
using Base64
import UUIDs

using ..Types
using ..AppContext: ServerContext, MCPContext
using ..Errors: MCPRequestError, MCP_PARSE_ERROR, MCP_INVALID_REQUEST,
    MCP_METHOD_NOT_FOUND, MCP_INVALID_PARAMS, MCP_INTERNAL_ERROR,
    MCP_HEADER_MISMATCH,
    MCP_UNSUPPORTED_PROTOCOL_VERSION, MCP_RESOURCE_NOT_FOUND
using ..Reflection
using ..AutoDoc
using ..PubSub
using ..Util: response_bytes
using ..Streaming: StreamEvent, FinalEvent, ErrorEvent, StreamCancelled,
    EventStream, enqueue!, start_stream!, pump_stream, drain_stream!,
    cancel_stream!, check_cancelled,
    STREAM_BUFFER_SIZE, stream_sse
import ..Streaming: emit, normalize_event

export register_tool!, register_prompt!, register_resource!, register_resource_folder!,
    mcp_stream, emit, progress, check_cancelled

# This server is dual-era: it serves the modern, stateless 2026-07-28 revision
# and the legacy initialize-handshake revision that mainstream clients speak.
# Era is a property of the request (its `_meta` or method), not the transport.
const MODERN_VERSIONS = ["2026-07-28"]
const LATEST_MODERN_VERSION = "2026-07-28"

# Legacy (initialize-handshake) revisions, newest first.
const LEGACY_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
const LATEST_LEGACY = "2025-11-25"

# Kept for backwards compatibility: the latest modern revision is the protocol
# version advertised by the stateless path.
const PROTOCOL_VERSION = LATEST_MODERN_VERSION

# Every revision this server understands, across both eras (advertised by
# `server/discover` and returned in unsupported-version errors).
const SUPPORTED_VERSIONS = vcat(MODERN_VERSIONS, LEGACY_VERSIONS)

# `structuredContent` results were introduced in the 2025-06-18 revision.
const STRUCTURED_CONTENT_VERSION = "2025-06-18"

# Reserved `_meta` keys.
const META_KEY = "_meta"
const META_PROTOCOL = "io.modelcontextprotocol/protocolVersion"
const META_CLIENT_INFO = "io.modelcontextprotocol/clientInfo"
const META_CLIENT_CAPABILITIES = "io.modelcontextprotocol/clientCapabilities"
const META_SERVER_INFO = "io.modelcontextprotocol/serverInfo"

# Cache hints for list/discovery results (SEP-2549). Supported versions and
# instructions are static, but discovery's capabilities are derived from the
# mutable tool/prompt/resource registries, so a cached discovery response goes
# stale the moment anything is registered. Both hints are therefore 0 (no
# caching); `list_changed` notifications cover the list case.
const DISCOVER_TTL_MS = 0
const LIST_TTL_MS = 0

"""
    negotiate_version(client_version) :: String

Negotiate the protocol version for a legacy `initialize` handshake: echo the
client's version when it is a supported legacy revision, otherwise fall back to
the latest legacy revision and let the client decide whether it can proceed.
"""
function negotiate_version(client_version::Union{Nothing,AbstractString})::String
    if !isnothing(client_version) && client_version in LEGACY_VERSIONS
        return String(client_version)
    end
    return LATEST_LEGACY
end

# Whether a negotiated (legacy) version predates `structuredContent`.
supports_structured_content(version::AbstractString)::Bool = version >= STRUCTURED_CONTENT_VERSION

# `icons` on resource entries were introduced in the same 2025-06-18 revision;
# older clients may reject unknown fields, so entries gate the field by version.
supports_resource_icons(version::AbstractString)::Bool = version >= STRUCTURED_CONTENT_VERSION

# ----------------------------------------------------------------------------
# Submodules
# ----------------------------------------------------------------------------

include("mcp/serialization.jl")  # schemas, argument coercion, content blocks, envelopes
include("mcp/errors.jl")         # error results and request validation
include("mcp/streams.jl")        # streaming event model, channels, wire mapping
include("mcp/sessions.jl")       # legacy Streamable HTTP sessions (Mcp-Session-Id)
include("mcp/tools.jl")          # tools/list, tools/call
include("mcp/prompts.jl")        # prompts/list, prompts/get
include("mcp/resources.jl")      # resources/list, resources/templates/list, resources/read
include("mcp/subscriptions.jl")  # subscriptions/listen, resources/subscribe, notify_*

# ----------------------------------------------------------------------------
# Discovery / initialization
# ----------------------------------------------------------------------------

# Capabilities advertised in both `server/discover` and `initialize`: tools are
# always served; prompts and resources only when at least one is registered.
# Registration functions push list-changed notifications, so every advertised
# `listChanged` flag is truthful; resources also support subscriptions.
function server_capabilities(ctx::ServerContext)::Dict{String,Any}
    capabilities = Dict{String,Any}(
        "tools" => Dict{String,Any}("listChanged" => true)
    )
    if !isempty(ctx.mcp.prompts)
        capabilities["prompts"] = Dict{String,Any}("listChanged" => true)
    end
    if has_resources(ctx)
        capabilities["resources"] = Dict{String,Any}("subscribe" => true, "listChanged" => true)
    end
    return capabilities
end

function discover_result(ctx::ServerContext)::Dict{String,Any}
    result = Dict{String,Any}(
        "supportedVersions" => copy(SUPPORTED_VERSIONS),
        "capabilities" => server_capabilities(ctx),
        "ttlMs" => DISCOVER_TTL_MS,
        "cacheScope" => "public",
    )
    if !isnothing(ctx.mcp.instructions)
        result["instructions"] = ctx.mcp.instructions
    end
    return result
end

"""
    initialize_result(ctx, params; session=nothing) :: Dict

Build the legacy `initialize` response. The client's version is echoed when
supported, otherwise the latest legacy revision is offered; the negotiated
version is remembered on `session` (or on the context-wide anonymous state for
stdio and header-less HTTP clients) for later feature gating.
"""
function initialize_result(ctx::ServerContext, params; session::Union{Nothing,MCPSession}=nothing)::Dict{String,Any}
    client_version = get(params, "protocolVersion", nothing)
    client_version isa AbstractString || (client_version = nothing)
    negotiated = negotiate_version(client_version)
    # A header-less initialize arms the context-wide anonymous state; a session
    # is armed on itself. Delivery additionally requires a completed handshake.
    set_handshake!(ctx, session, negotiated)

    result = Dict{String,Any}(
        "protocolVersion" => negotiated,
        "capabilities" => server_capabilities(ctx),
        "serverInfo" => Dict{String,Any}(
            "name" => ctx.mcp.server_name[],
            "version" => ctx.mcp.server_version[],
        ),
    )
    if !isnothing(ctx.mcp.instructions)
        result["instructions"] = ctx.mcp.instructions
    end
    return result
end

# ----------------------------------------------------------------------------
# Dispatch
# ----------------------------------------------------------------------------

# Transport agnostic dispatch. Returns the JSON-RPC response body together with
# the HTTP status code that should be used for it (stdio ignores the status).
# A streamed `tools/call` returns its `StreamedCall` and a `subscriptions/listen`
# returns its `ListenCall`; the transport consumes those directly.
function dispatch(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, method::String, payload;
                  era::Symbol=:legacy,
                  session::Union{Nothing,MCPSession}=nothing)::Tuple{Union{Dict{String,Any},StreamedCall,ListenCall},Int}
    modern = era === :modern
    version = modern ? PROTOCOL_VERSION : legacy_version(ctx, session)

    if method == "initialize"
        # initialize exists only in the legacy era.
        modern && return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
        return result_response(ctx, id,
                               initialize_result(ctx, request_params(payload); session=session))
    elseif method == "server/discover"
        return result_response(ctx, id, discover_result(ctx); modern=modern)
    elseif method == "tools/list"
        return result_response(ctx, id, tools_list(ctx; modern=modern); modern=modern)
    elseif method == "tools/call"
        return call_tool(ctx, req, id, request_params(payload); modern=modern, version=version)
    elseif method == "prompts/list"
        return result_response(ctx, id, prompts_list(ctx; modern=modern); modern=modern)
    elseif method == "prompts/get"
        return get_prompt(ctx, req, id, request_params(payload); modern=modern)
    elseif method == "resources/list"
        return result_response(ctx, id, resources_list(ctx; modern=modern, version=version);
                               modern=modern)
    elseif method == "resources/templates/list"
        return result_response(ctx, id, resource_templates_list(ctx; modern=modern, version=version);
                               modern=modern)
    elseif method == "resources/read"
        return read_resource(ctx, req, id, request_params(payload); modern=modern)
    elseif method == "subscriptions/listen"
        # subscriptions/listen exists only in the modern era.
        modern || return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
        return listen_call(ctx, req, id, request_params(payload))
    elseif method == "resources/subscribe"
        modern && return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
        return subscribe_resource_legacy(ctx, id, request_params(payload); session=session)
    elseif method == "resources/unsubscribe"
        modern && return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
        return unsubscribe_resource_legacy(ctx, id, request_params(payload); session=session)
    elseif method == "ping"
        # ping was removed from the modern era; it exists only in legacy.
        modern && return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
        return result_response(ctx, id, Dict{String,Any}())
    else
        return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
    end
end

# The `params` object of a request, empty when absent or not an object.
function request_params(payload)::AbstractDict
    params = get(payload, "params", Dict{String,Any}())
    return params isa AbstractDict ? params : Dict{String,Any}()
end

# ----------------------------------------------------------------------------
# Entry points
# ----------------------------------------------------------------------------

# Classify a parsed JSON-RPC message by shape: request (method + id),
# notification (method, no id), client response (result/error + id, no method),
# or invalid. Returns a Symbol.
function message_shape(payload)::Symbol
    payload isa AbstractDict || return :invalid
    has_method = haskey(payload, "method")
    has_id = haskey(payload, "id") && !isnothing(payload["id"])
    if has_method
        return has_id ? :request : :notification
    end
    if has_id && (haskey(payload, "result") || haskey(payload, "error"))
        return :client_response
    end
    return :invalid
end

"""
    validate_envelope(payload) :: Union{Nothing,Dict}

Enforce the JSON-RPC 2.0 envelope MCP requires: `jsonrpc` must be exactly
`"2.0"`, `method` must be a string, and an `id` may only be a string or a
number (a null id is forbidden by the MCP schema). Returns an error body, or
`nothing` when the envelope is well formed.
"""
function validate_envelope(payload)::Union{Nothing,Dict{String,Any}}
    version = get(payload, "jsonrpc", nothing)
    if !(version isa AbstractString) || String(version) != "2.0"
        return error_body(get(payload, "id", nothing), MCP_INVALID_REQUEST,
                          "Invalid Request: jsonrpc must be exactly \"2.0\"")
    end

    method = get(payload, "method", nothing)
    if !(method isa AbstractString)
        return error_body(get(payload, "id", nothing), MCP_INVALID_REQUEST, "Invalid Request")
    end

    if haskey(payload, "id")
        id = payload["id"]
        if !(id isa AbstractString || (id isa Integer && !(id isa Bool)))
            return error_body(nothing, MCP_INVALID_REQUEST,
                              "Invalid Request: id must be a string or a number")
        end
    end
    return nothing
end

# Handle a single parsed JSON-RPC message. Returns `(body, status)`, where
# `body` is `nothing` for notifications and client responses (no response is
# written), a `StreamedCall` for a streamed tools/call, a `ListenCall` for a
# `subscriptions/listen` stream, or a JSON-RPC body. `session` carries the
# legacy Streamable HTTP session resolved by the transport, when any.
function process(ctx::ServerContext, payload, req::Union{Nothing,HTTP.Request};
                 session::Union{Nothing,MCPSession}=nothing)::Tuple{Union{Nothing,Dict{String,Any},StreamedCall,ListenCall},Int}
    shape = message_shape(payload)

    if shape === :invalid
        id = payload isa AbstractDict ? get(payload, "id", nothing) : nothing
        return error_body(id, MCP_INVALID_REQUEST, "Invalid Request"), 400
    end

    if shape === :client_response
        # The server sends no server-to-client requests, so acknowledge and drop.
        return nothing, 202
    end

    envelope = validate_envelope(payload)
    isnothing(envelope) || return envelope, 400

    method = payload["method"]
    method = String(method)

    if shape === :notification
        if method == "notifications/initialized"
            mark_initialized!(ctx, session)
        elseif method == "notifications/cancelled" && req === nothing
            # Only routeless (stdio) listen streams can be cancelled in-band;
            # on HTTP a notification can arrive on any connection (see
            # `cancel_listen!`). Per JSON-RPC, a cancelled request gets no
            # response.
            params = get(payload, "params", nothing)
            params isa AbstractDict || return nothing, 202
            request_id = get(params, "requestId", nothing)
            request_id === nothing || cancel_listen!(ctx, request_id)
        end
        return nothing, 202
    end

    id = payload["id"]
    params = request_params(payload)

    era = request_era(req, method, params)
    if era === :modern
        try
            validate_modern_request(ctx, req, method, params)
        catch error
            error isa MCPRequestError || rethrow()
            return request_error_body(id, error), 400
        end
    end

    return dispatch(ctx, req, id, method, payload; era=era, session=session)
end

# The transport adapter decodes the request body before middleware runs, so the
# stream's own message carries headers only; `decorate_request` stashes the
# buffered request (body included) on the shared request context.
function buffered_request(stream::HTTP.Stream)::HTTP.Request
    request = get(stream.message.context, :buffered_request, stream.message)
    return request isa HTTP.Request ? request : stream.message
end

"""
    accepts_event_stream(req) :: Bool

Whether the request's `Accept` header allows a `text/event-stream` reply.
An explicit `text/event-stream` range decides on its own (`q=0` refuses);
otherwise `text/*` or `*/*` with a positive `q` accepts. A request with no
`Accept` header is treated as JSON-only, which keeps legacy clients on exactly
today's bytes.
"""
function accepts_event_stream(req::HTTP.Request)::Bool
    # `Accept` may be spread across repeated header entries; gather them all.
    accept = String[]
    for (key, value) in req.headers
        lowercase(String(key)) == "accept" && push!(accept, String(value))
    end
    isempty(accept) && return false

    wildcard = false
    for header in accept
        for entry in split(header, ',')
            fields = split(entry, ';')
            media = lowercase(strip(fields[1]))
            isempty(media) && continue
            # Media-range parameters: `q` weights the range (default 1.0); a
            # malformed weight is read as a refusal rather than as acceptance.
            q = 1.0
            for field in fields[2:end]
                part = split(field, '='; limit=2)
                if length(part) == 2 && lowercase(strip(part[1])) == "q"
                    q = something(tryparse(Float64, strip(part[2])), 0.0)
                end
            end
            # An exact `text/event-stream` range decides on its own; a wildcard
            # only opts in, it never overrides an exact refusal.
            if media == "text/event-stream"
                return q > 0
            elseif (media == "text/*" || media == "*/*") && q > 0
                wildcard = true
            end
        end
    end
    return wildcard
end

function write_json_response(stream::HTTP.Stream, body; status::Int=200,
                             headers::Vector{Pair{String,String}}=Pair{String,String}[])
    return write_stream_response(stream, status, "application/json; charset=utf-8", JSON.json(body);
                                 headers=headers)
end

function write_sse_frame(stream::HTTP.Stream, payload)
    write(stream, "event: message\n")
    write(stream, "data: ", JSON.json(payload), "\n\n")
    flush(stream)
    return nothing
end

"""
    request_is_modern(req, payload) :: Bool

Whether a parsed HTTP request belongs to the modern (stateless) era: its
message carries `_meta.protocolVersion`, its method is `server/discover`, or
the `MCP-Protocol-Version` header names a modern revision. Sessions exist only
in the legacy era, so modern requests never resolve one.
"""
function request_is_modern(req::HTTP.Request, payload)::Bool
    if payload isa AbstractDict
        method = get(payload, "method", nothing)
        method isa AbstractString || (method = "")
        return request_era(req, String(method), request_params(payload)) === :modern
    end
    return request_era(req, "", Dict{String,Any}()) === :modern
end

"""
    process_batch(ctx, payload, req; session) :: (body, status)

Handle a JSON-RPC batch. Batching existed only in the `2025-03-26` revision
(it was removed in `2025-06-18`), so a batch is accepted only when the
effective legacy version is exactly that revision. Notifications produce no
entries; a batch of only notifications answers `202` with no body. Streamed
tool calls are drained to their terminal JSON body (batches never upgrade to
SSE), and `subscriptions/listen` is rejected because it is a modern-only
stream.
"""
function process_batch(ctx::ServerContext, payload::AbstractVector,
                       req::Union{Nothing,HTTP.Request};
                       session::Union{Nothing,MCPSession}=nothing)
    isempty(payload) && return error_body(nothing, MCP_INVALID_REQUEST, "Invalid Request: empty batch"), 400

    if request_era(req, "", Dict{String,Any}()) === :modern
        return error_body(nothing, MCP_INVALID_REQUEST,
                          "Batch requests are not supported in the modern era"), 400
    end

    version = legacy_version(ctx, session)
    version == "2025-03-26" || return error_body(
        nothing, MCP_INVALID_REQUEST,
        "Batch requests require the 2025-03-26 protocol revision"), 400

    responses = Any[]
    for entry in payload
        body, _ = process(ctx, entry, req; session=session)
        if body isa StreamedCall
            body = streamed_body(ctx, body, drain_stream!(body.stream))
        elseif body isa ListenCall
            cancel_stream!(body.stream)
            body = error_body(body.id, MCP_INVALID_REQUEST,
                              "subscriptions/listen is not available in a batch")
        end
        isnothing(body) || push!(responses, body)
    end

    isempty(responses) && return nothing, 202
    return responses, 200
end

"""
    handle(ctx::ServerContext, stream::HTTP.Stream)

Streamable HTTP transport entry point. The `POST` route is registered as a
streaming route, so both the JSON and the SSE replies are written directly to
the raw stream:

- requests that are not `tools/call`, or whose tool never emits a
  notification, are answered with the exact JSON bytes the buffered route used
  to produce;
- a streamed call whose first event is a notification upgrades to SSE
  (`text/event-stream`, `Cache-Control: no-cache`, `X-Accel-Buffering: no`),
  flushes every frame, and keeps the stream alive with `: keepalive` comments
  while the producer is idle.

Origin checks, modern header validation, and body parsing all run before any
streaming starts. Legacy HTTP clients get a session id from `initialize` (see
`mcp/sessions.jl`); clients that echo it are isolated, while header-less
requests keep using the context-wide anonymous state.
"""
function handle(ctx::ServerContext, stream::HTTP.Stream)
    req = buffered_request(stream)

    origin_response = check_origin(ctx, req)
    if !isnothing(origin_response)
        return write_stream_response(stream, origin_response.status, "text/plain; charset=utf-8", "Forbidden")
    end

    # Explicit Content-Type: only JSON bodies are accepted. Accept-header
    # handling is deliberately lenient — clients that send no or partial Accept
    # headers still work.
    content_type = HTTP.header(req, "Content-Type", "")
    if !startswith(String(content_type), "application/json")
        return write_stream_response(stream, 415, "text/plain", "Unsupported Media Type")
    end

    # Version header handling is lenient for legacy traffic (no mirroring
    # required), but an unknown version is worth surfacing. Modern requests are
    # strictly validated later, so this is informational only.
    header_version = HTTP.header(req, "MCP-Protocol-Version", "")
    if !isempty(header_version) && !(strip(String(header_version)) in SUPPORTED_VERSIONS)
        @debug "Client requested unsupported protocol version" client_version=String(header_version) supported=SUPPORTED_VERSIONS
    end

    payload = try
        JSON.parse(String(req.body))
    catch
        return write_json_response(stream, error_body(nothing, MCP_PARSE_ERROR, "Parse error"); status=400)
    end

    modern = request_is_modern(req, payload)

    # Sessions only exist in the legacy era. A supplied id must name a live
    # session (404 otherwise, per the Streamable HTTP transport).
    session = nothing
    had_session_header = false
    if !modern
        resolved = resolve_session_or_error(ctx, req)
        if resolved isa Tuple
            status, body = resolved
            return write_json_response(stream, body; status=status)
        elseif resolved isa MCPSession
            session = resolved
            had_session_header = true
        end
    end

    if payload isa AbstractVector
        body, status = process_batch(ctx, payload, req; session=session)
        isnothing(body) && return write_stream_response(stream, status, "text/plain; charset=utf-8", "")
        return write_json_response(stream, body; status=status)
    end

    method = payload isa AbstractDict ? get(payload, "method", "") : ""

    # A header-less initialize mints a session and returns its id; the response
    # is the only place the client learns it.
    if !modern && !had_session_header && method == "initialize"
        session = new_session!(ctx)
    end

    body, status = process(ctx, payload, req; session=session)

    response_headers = Pair{String,String}[]
    if !modern && method == "initialize" && session isa MCPSession
        had_session_header || mirror_anonymous!(ctx, session)
        push!(response_headers, SESSION_HEADER => session.id)
    end

    if body isa StreamedCall
        return stream_call(ctx, stream, req, body)
    elseif body isa ListenCall
        return stream_listen_call(ctx, stream, req, body)
    end
    isnothing(body) && return write_stream_response(stream, status, "text/plain; charset=utf-8", "")
    return write_json_response(stream, body; status=status, headers=response_headers)
end

"""
    stream_call(ctx, stream, req, call::StreamedCall)

Consume one streamed `tools/call`. The first event decides the wire shape:
a terminal event (or a drained channel) stays plain JSON, while a notification
upgrades the response to SSE. On a failed frame write (client disconnect) the
channel is closed, which releases a producer blocked in `put!`.
"""
function stream_call(ctx::ServerContext, stream::HTTP.Stream, req::HTTP.Request, call::StreamedCall)
    token = call.stream.protocol.token

    if token === nothing || !accepts_event_stream(req)
        terminal = drain_stream!(call.stream)
        return write_json_response(stream, streamed_body(ctx, call, terminal))
    end

    first = try
        take!(call.stream.channel)
    catch error
        error isa InvalidStateException || rethrow()
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
            isnothing(body) || write_sse_frame(stream, body)
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
    write_stream_response(stream, status, content_type, body; headers=[])

Write a complete, non-streaming HTTP response directly to a raw `HTTP.Stream`.
The MCP `GET` route is registered as a streaming route (so it can hold the
connection open for SSE), so its fixed-body replies are written by hand.
"""
function write_stream_response(stream::HTTP.Stream, status::Int, content_type::String, body::AbstractString;
                               headers::Vector{Pair{String,String}}=Pair{String,String}[])
    HTTP.setstatus(stream, status)
    HTTP.setheader(stream, "Content-Type" => content_type)
    # These fixed-body replies are written by a streaming handler, so the server
    # cannot manage connection reuse for them; close explicitly to keep clients
    # from pooling a socket that will not be reused.
    HTTP.setheader(stream, "Connection" => "close")
    for (name, value) in headers
        HTTP.setheader(stream, name => value)
    end
    HTTP.setheader(stream, "Content-Length" => string(ncodeunits(body)))
    HTTP.startwrite(stream)
    write(stream, body)
    HTTP.closewrite(stream)
    return nothing
end

"""
    handle_get(ctx::ServerContext, stream::HTTP.Stream)

HTTP `GET` on the MCP endpoint, registered through the streaming route so it can
either answer with a fixed body or hold the connection open for SSE.

- A GET declaring a modern `MCP-Protocol-Version` gets `405` (the modern era
  removed the GET endpoint).
- A GET with `Accept: text/event-stream` opens the legacy server→client
  notification stream and keeps it open until the client disconnects.
- Any other GET returns a JSON health body, which lets clients health-check the
  endpoint.
"""
function handle_get(ctx::ServerContext, stream::HTTP.Stream)
    req = stream.message

    # The legacy notification stream is a privileged sink too: without this
    # check a DNS-rebinding page could read server-initiated notifications. The
    # guard runs before every GET reply, matching `handle`.
    origin_response = check_origin(ctx, req)
    if !isnothing(origin_response)
        return write_stream_response(stream, origin_response.status, "text/plain; charset=utf-8", "Forbidden")
    end

    version = HTTP.header(req, "MCP-Protocol-Version", "")
    if strip(String(version)) in MODERN_VERSIONS
        return write_stream_response(stream, 405, "text/plain", "Method Not Allowed";
                                     headers=["Allow" => "POST"])
    end

    resolved = resolve_session_or_error(ctx, req)
    if resolved isa Tuple
        status, body = resolved
        return write_json_response(stream, body; status=status)
    end
    session = resolved isa MCPSession ? resolved : nothing

    accept = join((String(v) for (k, v) in req.headers
                   if lowercase(String(k)) == "accept"), ",")
    if occursin("text/event-stream", accept)
        return stream_notifications(ctx, stream; session=session)
    end

    body = Dict{String,Any}(
        "status" => "ok",
        "protocol_version" => legacy_version(ctx, session),
    )
    return write_json_response(stream, body)
end

"""
    handle_delete(ctx, req) :: HTTP.Response

Terminate the legacy session named by `Mcp-Session-Id`. A DELETE without the
header is `405` (the server does not accept anonymous termination), an unknown
or expired id is `404`, and the modern era — which has no sessions — is `405`.
An accepted termination closes the session's notification streams and removes
its state; later requests naming it get `404`.
"""
function handle_delete(ctx::ServerContext, req::HTTP.Request)::HTTP.Response
    header_version = mcp_standard_header(req, "MCP-Protocol-Version")
    if header_version isa String && strip(String(header_version)) in MODERN_VERSIONS
        return HTTP.Response(405, ["Allow" => "POST, GET"], "Method Not Allowed")
    end

    resolved = resolve_session_or_error(ctx, req)
    if resolved isa Tuple
        status, body = resolved
        return HTTP.Response(status, ["Content-Type" => "application/json; charset=utf-8"],
                             JSON.json(body))
    elseif resolved === nothing
        return HTTP.Response(405, ["Allow" => "POST, GET"], "Method Not Allowed")
    end

    session = resolved::MCPSession
    terminate_session!(ctx, session)
    lock(ctx.mcp.sessions_lock) do
        delete!(ctx.mcp.sessions, session.id)
    end
    return HTTP.Response(200, ["Content-Type" => "application/json; charset=utf-8"],
                         JSON.json(Dict{String,Any}("status" => "terminated")))
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
        error isa PubSub.CapacityError || rethrow()
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
            event isa SubscriptionNotification || return true
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
            session isa MCPSession && remove_sink!(session, sub)
        end)
end

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
            isempty(message) && continue

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

            isnothing(body) && continue
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
        error isa PubSub.CapacityError || rethrow()
        @warn "stdio legacy notification sink disabled: subscription capacity exhausted"
        return nothing
    end
    push!(notifier.subs, sub)

    source = EventStream(sub.queue, nothing)
    task = @async pump_stream(source,
        event -> begin
            event isa SubscriptionNotification || return true
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
        task === current_task() && continue
        try
            wait(task)
        catch
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
            isnothing(body) || respond(notifier, body)
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

end # module MCP
