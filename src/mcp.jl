module MCP

using HTTP
using JSON
using Base64

using ..Types
using ..AppContext: ServerContext, MCPContext
using ..Errors: MCPRequestError, MCP_PARSE_ERROR, MCP_INVALID_REQUEST,
    MCP_METHOD_NOT_FOUND, MCP_INVALID_PARAMS, MCP_INTERNAL_ERROR,
    MCP_HEADER_MISMATCH, MCP_MISSING_REQUIRED_CLIENT_CAPABILITY,
    MCP_UNSUPPORTED_PROTOCOL_VERSION
using ..Reflection
using ..AutoDoc
using ..Util: response_bytes

export register_tool!, register_prompt!

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

# Cache hints for list/discovery results (SEP-2549). Discovery advertises a
# static shape for the process lifetime, so a long TTL fits; list methods
# default to 0 (immediately stale) because the registries are mutable at
# runtime and we advertise `listChanged: false`, so we never push a change
# notification.
const DISCOVER_TTL_MS = 3_600_000
const LIST_TTL_MS = 0

# Interval between keep-alive comments on the legacy SSE notification stream.
const SSE_KEEPALIVE_SECONDS = 3

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

# ----------------------------------------------------------------------------
# Submodules
# ----------------------------------------------------------------------------

include("mcp/serialization.jl")  # schemas, argument coercion, content blocks, envelopes
include("mcp/errors.jl")         # error results and request validation
include("mcp/tools.jl")          # tools/list, tools/call
include("mcp/prompts.jl")        # prompts/list, prompts/get

# ----------------------------------------------------------------------------
# Discovery / initialization
# ----------------------------------------------------------------------------

# Capabilities advertised in both `server/discover` and `initialize`: tools are
# always served; prompts only when at least one is registered.
function server_capabilities(ctx::ServerContext; legacy::Bool=false)::Dict{String,Any}
    capabilities = Dict{String,Any}(
        "tools" => legacy ? Dict{String,Any}("listChanged" => false) : Dict{String,Any}()
    )
    if !isempty(ctx.mcp.prompts)
        capabilities["prompts"] = legacy ? Dict{String,Any}("listChanged" => false) : Dict{String,Any}()
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
    initialize_result(ctx, params) :: Dict

Build the legacy `initialize` response. The client's version is echoed when
supported, otherwise the latest legacy revision is offered; the negotiated
version is remembered on the context for later feature gating.
"""
function initialize_result(ctx::ServerContext, params)::Dict{String,Any}
    client_version = get(params, "protocolVersion", nothing)
    client_version isa AbstractString || (client_version = nothing)
    negotiated = negotiate_version(client_version)
    ctx.mcp.session_version[] = negotiated

    result = Dict{String,Any}(
        "protocolVersion" => negotiated,
        "capabilities" => server_capabilities(ctx; legacy=true),
        "serverInfo" => Dict{String,Any}(
            "name" => ctx.mcp.server_name,
            "version" => ctx.mcp.server_version,
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
function dispatch(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, method::String, payload;
                  era::Symbol=:legacy)::Tuple{Dict{String,Any},Int}
    modern = era === :modern
    version = modern ? PROTOCOL_VERSION : ctx.mcp.session_version[]

    if method == "initialize"
        # initialize exists only in the legacy era.
        modern && return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
        return result_body(id, initialize_result(ctx, get(payload, "params", Dict{String,Any}()))), 200
    elseif method == "server/discover"
        return result_body(id, modern_envelope(ctx, discover_result(ctx))), 200
    elseif method == "tools/list"
        result = tools_list(ctx; modern=modern)
        modern && (result = modern_envelope(ctx, result))
        return result_body(id, result), 200
    elseif method == "tools/call"
        params = get(payload, "params", Dict{String,Any}())
        params isa AbstractDict || (params = Dict{String,Any}())
        return call_tool(ctx, req, id, params; modern=modern, version=version)
    elseif method == "prompts/list"
        result = prompts_list(ctx; modern=modern)
        modern && (result = modern_envelope(ctx, result))
        return result_body(id, result), 200
    elseif method == "prompts/get"
        params = get(payload, "params", Dict{String,Any}())
        params isa AbstractDict || (params = Dict{String,Any}())
        return get_prompt(ctx, req, id, params; modern=modern)
    elseif method == "ping"
        # ping was removed from the modern era; it exists only in legacy.
        modern && return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
        return result_body(id, Dict{String,Any}()), 200
    else
        return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
    end
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

# Handle a single parsed JSON-RPC message. Returns `(body, status)`, where
# `body` is `nothing` for notifications and client responses (no response is
# written).
function process(ctx::ServerContext, payload, req::Union{Nothing,HTTP.Request})::Tuple{Union{Nothing,Dict{String,Any}},Int}
    shape = message_shape(payload)

    if shape === :invalid
        id = payload isa AbstractDict ? get(payload, "id", nothing) : nothing
        return error_body(id, MCP_INVALID_REQUEST, "Invalid Request"), 400
    end

    if shape === :client_response
        # The server sends no server-to-client requests, so acknowledge and drop.
        return nothing, 202
    end

    method = payload["method"]
    method isa AbstractString || return error_body(get(payload, "id", nothing), MCP_INVALID_REQUEST, "Invalid Request"), 400
    method = String(method)

    if shape === :notification
        method == "notifications/initialized" && (ctx.mcp.initialized[] = true)
        return nothing, 202
    end

    id = payload["id"]
    params = get(payload, "params", Dict{String,Any}())
    params isa AbstractDict || (params = Dict{String,Any}())

    era = request_era(req, method, params)
    if era === :modern
        try
            validate_modern_request(ctx, req, method, params)
        catch error
            error isa MCPRequestError || rethrow()
            return error_body(id, error.code, error.message, error.data), 400
        end
    end

    return dispatch(ctx, req, id, method, payload; era=era)
end

"""
    handle(ctx::ServerContext, req::HTTP.Request) :: HTTP.Response

Streamable HTTP transport entry point. Handles a single JSON-RPC request or
notification over a stateless POST.
"""
function handle(ctx::ServerContext, req::HTTP.Request)::HTTP.Response
    origin_response = check_origin(ctx, req)
    isnothing(origin_response) || return origin_response

    # Explicit Content-Type: only JSON bodies are accepted. Accept-header
    # handling is deliberately lenient — clients that send no or partial Accept
    # headers still work.
    content_type = HTTP.header(req, "Content-Type", "")
    startswith(String(content_type), "application/json") ||
        return HTTP.Response(415, ["Content-Type" => "text/plain"], "Unsupported Media Type")

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
        return json_response(error_body(nothing, MCP_PARSE_ERROR, "Parse error"); status=400)
    end

    body, status = process(ctx, payload, req)
    return isnothing(body) ? HTTP.Response(status) : json_response(body; status=status)
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

    version = HTTP.header(req, "MCP-Protocol-Version", "")
    if strip(String(version)) in MODERN_VERSIONS
        return write_stream_response(stream, 405, "text/plain", "Method Not Allowed";
                                     headers=["Allow" => "POST"])
    end

    accept = join((String(v) for (k, v) in req.headers
                   if lowercase(String(k)) == "accept"), ",")
    if occursin("text/event-stream", accept)
        return stream_notifications(stream)
    end

    body = JSON.json(Dict{String,Any}(
        "status" => "ok",
        "protocol_version" => ctx.mcp.session_version[],
    ))
    return write_stream_response(stream, 200, "application/json; charset=utf-8", body)
end

"""
    stream_notifications(stream::HTTP.Stream)

Hold the legacy server→client notification channel open as an SSE stream. This
server emits no unsolicited notifications yet, so the stream carries a priming
comment followed by periodic keep-alive comments; it stays open until the client
disconnects. This is what stops mainstream clients from tearing the stream down
and reconnecting once per second.
"""
function stream_notifications(stream::HTTP.Stream)
    HTTP.setstatus(stream, 200)
    HTTP.setheader(stream, "Content-Type" => "text/event-stream")
    HTTP.setheader(stream, "Cache-Control" => "no-cache")
    HTTP.setheader(stream, "Connection" => "keep-alive")
    HTTP.startwrite(stream)

    try
        # Priming comment: lets the client see the stream is live immediately.
        write(stream, ": connected\n\n")
        flush(stream)
        while true
            sleep(SSE_KEEPALIVE_SECONDS)
            write(stream, ": keepalive\n\n")
            flush(stream)
        end
    catch
        # The client disconnected (write failed) — end the stream quietly.
    finally
        try
            HTTP.closewrite(stream)
        catch
        end
    end
    return nothing
end

"""
    stdio_loop(ctx::ServerContext; input=stdin, output=stdout)

stdio transport entry point. Reads newline-delimited JSON-RPC messages from
`input`, dispatches them, and writes responses to `output`. Notifications
produce no output. The loop returns when `input` reaches end-of-file, which is
the standard graceful-shutdown signal for stdio MCP servers.
"""
function stdio_loop(ctx::ServerContext; input::IO=stdin, output::IO=stdout)
    for line in eachline(input)
        message = strip(line)
        isempty(message) && continue

        payload = try
            JSON.parse(message)
        catch
            respond(output, error_body(nothing, MCP_PARSE_ERROR, "Parse error"))
            continue
        end

        body = try
            first(process(ctx, payload, nothing))
        catch
            error_body(nothing, MCP_INTERNAL_ERROR, "Internal error")
        end

        isnothing(body) && continue
        respond(output, body)
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
