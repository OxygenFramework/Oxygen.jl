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
using ..Util: text

export register_tool!

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
# static shape for the process lifetime, so a long TTL fits; `tools/list`
# defaults to 0 (immediately stale) because the tool registry is mutable at
# runtime and we advertise `tools.listChanged: false`, so we never push a
# change notification.
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
# Tool registration (the only write path to the registry)
# ----------------------------------------------------------------------------

"""
    normalize_descriptions(params) :: Dict{Symbol,String}

Coerce the explicit parameter description map (keys may be `Symbol` or `String`)
into a `Dict{Symbol,String}`. `nothing` yields an empty map.
"""
function normalize_descriptions(params)::Dict{Symbol,String}
    descriptions = Dict{Symbol,String}()
    params === nothing && return descriptions
    for (key, value) in pairs(params)
        descriptions[Symbol(key)] = string(value)
    end
    return descriptions
end

"""
    register_tool!(ctx::ServerContext, desc, params, func::Function; name=nothing)

Reflect on `func`, merge the explicit `params` descriptions, and store the
resulting `MCPTool` in `ctx.mcp.tools` keyed by its wire name.
"""
function register_tool!(ctx::ServerContext, desc, params, func::Function; name=nothing)
    info = Reflection.splitdef(func; start=1)
    descriptions = normalize_descriptions(params)

    method = first(methods(func))
    kwdecl = Base.kwarg_decl(method)
    has_context = :context in kwdecl
    has_request = :request in kwdecl

    argnames = Symbol[]
    mcp_params = MCPParam[]

    for p in info.args
        push!(argnames, p.name)
        push!(mcp_params, MCPParam(p, get(descriptions, p.name, "")))
    end

    for p in info.kwargs
        # `context` / `request` are injected by the framework, never part of the schema
        p.name in (:context, :request) && continue
        push!(mcp_params, MCPParam(p, get(descriptions, p.name, "")))
    end

    wirename = isnothing(name) ? string(info.name) : string(name)

    if haskey(ctx.mcp.tools, wirename)
        throw(ArgumentError("An MCP tool named `$wirename` is already registered"))
    end

    tool = MCPTool(wirename, string(desc), func, mcp_params, argnames, has_context, has_request)
    ctx.mcp.tools[wirename] = tool
    return tool
end

# ----------------------------------------------------------------------------
# Schema generation
# ----------------------------------------------------------------------------

# Rewrite the OpenAPI component refs emitted by `AutoDoc.convertobject!` into
# self-contained `$defs` refs (JSON Schema 2020-12).
function rewrite_refs!(value)
    if value isa AbstractDict
        for (key, item) in value
            if key == "\$ref" && item isa AbstractString
                value[key] = replace(item, "#/components/schemas/" => "#/\$defs/")
            else
                rewrite_refs!(item)
            end
        end
    elseif value isa AbstractVector
        for item in value
            rewrite_refs!(item)
        end
    end
    return value
end

"""
    typeschema(T) -> (schema, defs)

Build a self-contained JSON Schema fragment for the Julia type `T`. Any nested
struct definitions are returned in `defs` and referenced via `#/\$defs/<Name>`.
"""
function typeschema(T::Type)
    defs = Dict{String,Any}()
    nullable = AutoDoc.is_nullable_union(T)
    resolved = AutoDoc.resolve_union_type(T)

    if resolved === Union{} || resolved === Core.TypeofBottom
        resolved = T
    end

    schema = _typeschema(resolved, defs)
    nullable && (schema["nullable"] = true)
    return schema, defs
end

function _typeschema(T::Type, defs::Dict{String,Any})
    T = AutoDoc.unwrap_type(T)

    if AutoDoc.is_custom_struct(T)
        local_defs = Dict{String,Any}()
        AutoDoc.convertobject!(T, local_defs)
        for (_, value) in local_defs
            rewrite_refs!(value)
        end
        merge!(defs, local_defs)
        return Dict{String,Any}("\$ref" => "#/\$defs/$(nameof(T))")
    elseif T <: AbstractArray
        elem = AutoDoc.get_element_type(T)
        item_schema, item_defs = typeschema(elem)
        merge!(defs, item_defs)
        return Dict{String,Any}("type" => "array", "items" => item_schema)
    else
        schema = Dict{String,Any}("type" => AutoDoc.gettype(T))
        format = AutoDoc.getformat(T)
        !isnothing(format) && (schema["format"] = format)
        if T <: Enum
            schema["enum"] = collect(Int.(Base.Enums.instances(T)))
        end
        return schema
    end
end

function paramschema(p::MCPParam)
    schema, defs = typeschema(p.param.type)
    !isempty(p.description) && (schema["description"] = p.description)
    if p.param.hasdefault && !ismissing(p.param.default)
        schema["default"] = p.param.default
    end
    return schema, defs
end

"""
    inputschema(tool::MCPTool) :: Dict

Generate the JSON Schema describing a tool's expected arguments.
"""
function inputschema(tool::MCPTool)::Dict{String,Any}
    if isempty(tool.params)
        return Dict{String,Any}("type" => "object", "additionalProperties" => false)
    end

    properties = Dict{String,Any}()
    required = String[]
    defs = Dict{String,Any}()

    for p in tool.params
        name = String(p.param.name)
        schema, pdefs = paramschema(p)
        properties[name] = schema
        merge!(defs, pdefs)
        isrequired(p.param) && push!(required, name)
    end

    result = Dict{String,Any}("type" => "object", "properties" => properties)
    isempty(required) || (result["required"] = required)
    isempty(defs) || (result["\$defs"] = defs)
    return result
end

# ----------------------------------------------------------------------------
# Argument coercion
# ----------------------------------------------------------------------------

"""
    parse_tool_argument(::Type{T}, value)

Coerce a JSON-decoded `value` into the Julia type `T` declared on the handler.
"""
function parse_tool_argument(::Type{T}, value) where {T}
    resolved = AutoDoc.resolve_union_type(T)
    target = (resolved === Union{} || resolved === Core.TypeofBottom) ? T : resolved

    if value === nothing
        return nothing
    end

    if target === Any
        return value
    elseif value isa target
        return value
    elseif target <: AbstractString
        return string(value)
    elseif target <: Bool
        return value isa AbstractString ? parse(Bool, value) : convert(Bool, value)
    elseif target <: Integer
        return value isa AbstractString ? parse(target, value) : convert(target, value)
    elseif target <: AbstractFloat
        return value isa AbstractString ? parse(target, value) : convert(target, value)
    elseif target <: Enum
        return target(value isa AbstractString ? parse(Int, value) : Int(value))
    elseif AutoDoc.is_custom_struct(target) && value isa AbstractDict
        return Reflection.struct_builder(target, value)
    elseif target <: AbstractArray && value isa AbstractVector
        return Reflection.parse_array_value(target, value)
    else
        return convert(target, value)
    end
end

# ----------------------------------------------------------------------------
# Tool invocation
# ----------------------------------------------------------------------------

function getappcontext(ctx::ServerContext)
    app_ctx = ctx.app_context[]
    return ismissing(app_ctx) ? missing : app_ctx.payload
end

# Look up an argument by its String or Symbol key.
function argument_value(arguments, name::Symbol)
    key = string(name)
    haskey(arguments, key) && return (true, arguments[key])
    haskey(arguments, name) && return (true, arguments[name])
    return (false, nothing)
end

function resolve_argument!(pos_values::Vector{Any}, p::MCPParam, arguments)
    name = p.param.name
    found, value = argument_value(arguments, name)
    if found
        push!(pos_values, parse_tool_argument(p.param.type, value))
    elseif !isrequired(p.param)
        push!(pos_values, p.param.default)
    else
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required argument: $name"))
    end
    return pos_values
end

function resolve_kwarg!(kwpairs::Vector{Pair{Symbol,Any}}, p::MCPParam, arguments)
    name = p.param.name
    found, value = argument_value(arguments, name)
    if found
        push!(kwpairs, name => parse_tool_argument(p.param.type, value))
    elseif !isrequired(p.param)
        # Only forward the default when it is a concrete value; otherwise the
        # handler's own default should apply.
        !ismissing(p.param.default) && push!(kwpairs, name => p.param.default)
    else
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required argument: $name"))
    end
    return kwpairs
end

function invoke_tool(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, tool::MCPTool, arguments)
    pos_values = Any[]
    kwpairs = Pair{Symbol,Any}[]

    for p in tool.params
        if p.param.name in tool.argnames
            resolve_argument!(pos_values, p, arguments)
        else
            resolve_kwarg!(kwpairs, p, arguments)
        end
    end

    tool.has_context && push!(kwpairs, :context => getappcontext(ctx))
    tool.has_request && push!(kwpairs, :request => req)

    return tool.handler(pos_values...; kwpairs...)
end

# ----------------------------------------------------------------------------
# Result serialization
# ----------------------------------------------------------------------------

function text_result(content::String, structured_content=nothing)
    result = Dict{String,Any}(
        "content" => [Dict{String,Any}("type" => "text", "text" => content)],
        "isError" => false,
    )
    structured_content === nothing || (result["structuredContent"] = structured_content)
    return result
end

function toolresult(value)
    if value isa HTTP.Response
        return text_result(text(value))
    elseif value isa AbstractString
        return text_result(String(value))
    else
        encoded = JSON.json(value)
        # CallToolResult.structuredContent MUST be a JSON object per the MCP
        # spec; a scalar or array result has no valid structured form, so it is
        # omitted (the JSON still travels as text content).
        structured = startswith(lstrip(encoded), "{") ? JSON.parse(encoded) : nothing
        return text_result(encoded, structured)
    end
end

function toolerror_result(error)::Dict{String,Any}
    return Dict{String,Any}(
        "content" => [Dict{String,Any}("type" => "text", "text" => sprint(showerror, error))],
        "isError" => true,
    )
end

"""
    modern_envelope(ctx, result) :: Dict

Apply the modern-era result envelope to `result`: every modern result MUST carry
`resultType` (`"complete"`) and SHOULD identify the server via
`io.modelcontextprotocol/serverInfo` in the result `_meta`. Legacy results are
left untouched (legacy clients choke on unexpected `resultType`/`ttlMs`).
"""
function modern_envelope(ctx::ServerContext, result::Dict{String,Any})::Dict{String,Any}
    result["resultType"] = "complete"

    meta = get(result, META_KEY, nothing)
    meta isa AbstractDict || (meta = Dict{String,Any}())
    meta[META_SERVER_INFO] = Dict{String,Any}(
        "name" => ctx.mcp.server_name,
        "version" => ctx.mcp.server_version,
    )
    result[META_KEY] = meta
    return result
end

"""
    strip_unstructured!(result)

Drop `structuredContent` from a legacy tool result when the negotiated version
predates its introduction (2025-06-18); older clients reject unknown fields.
"""
function strip_unstructured!(result::Dict{String,Any})
    delete!(result, "structuredContent")
    return result
end

# ----------------------------------------------------------------------------
# JSON-RPC response helpers
# ----------------------------------------------------------------------------

function json_response(body; status::Int=200)::HTTP.Response
    payload = JSON.json(body)
    return HTTP.Response(status, ["Content-Type" => "application/json; charset=utf-8"], payload)
end

function result_body(id, result)::Dict{String,Any}
    return Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "result" => result)
end

function error_body(id, code::Int, message::String, data=nothing)::Dict{String,Any}
    error = Dict{String,Any}("code" => code, "message" => message)
    !isnothing(data) && (error["data"] = data)
    return Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "error" => error)
end

# ----------------------------------------------------------------------------
# Request validation
# ----------------------------------------------------------------------------

"""
    mcp_standard_header(req, name) :: Union{Nothing,String,Symbol}

Case-insensitive lookup of a standard MCP request header. Returns `nothing` when
absent, `:invalid` when the header is duplicated or carries unsafe bytes, and the
whitespace-stripped value otherwise.
"""
function mcp_standard_header(req::HTTP.Request, name::String)::Union{Nothing,String,Symbol}
    values = String[]
    target = lowercase(name)
    for (key, value) in req.headers
        lowercase(String(key)) == target || continue
        push!(values, String(value))
    end
    isempty(values) && return nothing
    length(values) > 1 && return :invalid
    value = String(strip(values[1]))
    all(b -> 0x20 <= b <= 0x7e || b == UInt8('\t'), codeunits(value)) || return :invalid
    return value
end

"""
    decode_header_value(value) :: Union{Nothing,String}

Decode a standard-header value per SEP-2243: a `=?base64?...?=` sentinel wraps a
Base64-encoded UTF-8 payload (used when the raw value is not header-safe). The
Base64 is validated strictly (canonical alphabet, correct padding, length a
multiple of four) and must decode to valid UTF-8. Returns `nothing` when the
value is a malformed sentinel; non-sentinel values are returned unchanged.
"""
function decode_header_value(value::String)::Union{Nothing,String}
    prefix = "=?base64?"
    suffix = "?="
    if startswith(value, prefix) && endswith(value, suffix) && length(value) >= length(prefix) + length(suffix)
        encoded = value[(length(prefix) + 1):(end - length(suffix))]
        occursin(r"^[A-Za-z0-9+/]+={0,2}$", encoded) || return nothing
        length(encoded) % 4 == 0 || return nothing
        decoded = try
            String(base64decode(encoded))
        catch
            return nothing
        end
        all(isvalid, decoded) || return nothing
        return decoded
    end
    return value
end

function check_origin(ctx::ServerContext, req::HTTP.Request)
    origin = HTTP.header(req, "Origin", nothing)
    (isnothing(origin) || isempty(origin)) && return nothing

    origin = String(origin)

    # Explicit allowlist always wins
    if origin in ctx.mcp.allowed_origins
        return nothing
    end

    # Same-host origins are permitted by default
    host = HTTP.header(req, "Host", nothing)
    if !isnothing(host)
        origin_host = try
            uri = HTTP.URI(origin)
            port = isnothing(uri.port) ? "" : ":" * string(uri.port)
            string(something(uri.host, "")) * port
        catch
            ""
        end
        if !isempty(origin_host) && origin_host == String(host)
            return nothing
        end
    end

    return HTTP.Response(403, "Forbidden")
end

"""
    request_era(req, method, params) :: Symbol

Classify a request by era. A request is modern iff its `params._meta` carries the
`io.modelcontextprotocol/protocolVersion` key, its method is `server/discover`
(modern-only), or — over HTTP — the `MCP-Protocol-Version` header names a modern
revision (era may be claimed by the headers alone). Everything else is legacy.
"""
function request_era(req::Union{Nothing,HTTP.Request}, method::String, params)::Symbol
    meta = get(params, META_KEY, nothing)
    if meta isa AbstractDict
        version = get(meta, META_PROTOCOL, nothing)
        version isa AbstractString && return :modern
    end

    method == "server/discover" && return :modern

    if req isa HTTP.Request
        header_version = mcp_standard_header(req, "MCP-Protocol-Version")
        header_version isa String && strip(header_version) in MODERN_VERSIONS && return :modern
    end

    return :legacy
end

"""
    validate_modern_request(ctx, req, method, params)

Enforce the modern-era (2026-07-28) per-request contract: a supported
`_meta.protocolVersion`, the required `_meta.clientCapabilities`, and — over
HTTP — mirrored standard headers (`MCP-Protocol-Version`, `Mcp-Method`, and
`Mcp-Name` for `tools/call`). Legacy requests skip all of this.
"""
function validate_modern_request(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, method::String, params)
    meta = get(params, META_KEY, Dict{String,Any}())
    meta isa AbstractDict || (meta = Dict{String,Any}())

    body_version = get(meta, META_PROTOCOL, nothing)
    if !(body_version isa AbstractString) || isempty(body_version)
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_PROTOCOL"))
    end

    if !(String(body_version) in MODERN_VERSIONS)
        throw(MCPRequestError(MCP_UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version", Dict{String,Any}(
            "supported" => copy(SUPPORTED_VERSIONS),
            "requested" => String(body_version),
        )))
    end

    if !haskey(meta, META_CLIENT_CAPABILITIES)
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_CLIENT_CAPABILITIES"))
    end

    # The remaining checks are specific to the Streamable HTTP transport.
    req === nothing && return nothing

    header_version = mcp_standard_header(req, "MCP-Protocol-Version")
    header_version === :invalid && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "MCP-Protocol-Version header is duplicated or contains unsafe characters"))
    header_version === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "Missing required MCP-Protocol-Version header"))
    String(header_version) != String(body_version) && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "Header mismatch: MCP-Protocol-Version header value '$header_version' does not match body value '$body_version'"))

    header_method = mcp_standard_header(req, "Mcp-Method")
    header_method === :invalid && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "Mcp-Method header is duplicated or contains unsafe characters"))
    header_method === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "Missing required Mcp-Method header"))
    String(header_method) != method && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "Header mismatch: Mcp-Method header value '$header_method' does not match body value '$method'"))

    if method == "tools/call"
        header_name = mcp_standard_header(req, "Mcp-Name")
        header_name === :invalid && throw(MCPRequestError(MCP_HEADER_MISMATCH,
            "Mcp-Name header is duplicated or contains unsafe characters"))
        header_name === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH,
            "Missing required Mcp-Name header"))
        decoded = decode_header_value(String(header_name))
        decoded === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH,
            "Mcp-Name header carries a malformed Base64 sentinel value"))
        body_name = get(params, "name", nothing)
        if !(body_name isa AbstractString) || decoded != String(body_name)
            throw(MCPRequestError(MCP_HEADER_MISMATCH,
                "Header mismatch: Mcp-Name header value '$decoded' does not match body value '$(body_name)'"))
        end
    end

    return nothing
end

# ----------------------------------------------------------------------------
# Methods
# ----------------------------------------------------------------------------

function discover_result(ctx::ServerContext)::Dict{String,Any}
    result = Dict{String,Any}(
        "supportedVersions" => copy(SUPPORTED_VERSIONS),
        "capabilities" => Dict{String,Any}("tools" => Dict{String,Any}()),
        "ttlMs" => DISCOVER_TTL_MS,
        "cacheScope" => "public",
    )
    if !isnothing(ctx.mcp.instructions)
        result["instructions"] = ctx.mcp.instructions
    end
    return result
end

function tools_list(ctx::ServerContext; modern::Bool=true)::Dict{String,Any}
    tools = Dict{String,Any}[]
    for name in sort(collect(keys(ctx.mcp.tools)))
        tool = ctx.mcp.tools[name]
        push!(tools, Dict{String,Any}(
            "name" => tool.name,
            "description" => tool.description,
            "inputSchema" => inputschema(tool),
        ))
    end
    result = Dict{String,Any}("tools" => tools)
    if modern
        result["ttlMs"] = LIST_TTL_MS
        result["cacheScope"] = "public"
    end
    return result
end

function call_tool(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params;
                   modern::Bool=false, version::String=LATEST_LEGACY)::Tuple{Dict{String,Any},Int}
    body_name = get(params, "name", nothing)
    if isnothing(body_name)
        return error_body(id, MCP_INVALID_PARAMS, "Missing tool name"), 200
    end

    wirename = String(body_name)
    tool = get(ctx.mcp.tools, wirename, nothing)
    if isnothing(tool)
        return error_body(id, MCP_INVALID_PARAMS, "Unknown tool: $wirename"), 200
    end

    arguments = get(params, "arguments", Dict{String,Any}())
    isnothing(arguments) && (arguments = Dict{String,Any}())
    if !(arguments isa AbstractDict)
        return error_body(id, MCP_INVALID_PARAMS, "Invalid arguments: expected an object"), 200
    end

    try
        value = invoke_tool(ctx, req, tool, arguments)
        result = toolresult(value)
        if !modern && !supports_structured_content(version)
            strip_unstructured!(result)
        end
        modern && (result = modern_envelope(ctx, result))
        return result_body(id, result), 200
    catch error
        if error isa MCPRequestError
            return error_body(id, error.code, error.message, error.data), 200
        end
        result = toolerror_result(error)
        modern && (result = modern_envelope(ctx, result))
        return result_body(id, result), 200
    end
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
        "capabilities" => Dict{String,Any}(
            "tools" => Dict{String,Any}("listChanged" => false),
        ),
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
