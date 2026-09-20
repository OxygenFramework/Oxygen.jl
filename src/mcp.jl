module MCP

using HTTP
using JSON
using Base64

using ..Types
using ..AppContext: ServerContext, MCPContext
using ..Errors: MCPRequestError, MCP_PARSE_ERROR, MCP_INVALID_REQUEST,
    MCP_METHOD_NOT_FOUND, MCP_INVALID_PARAMS, MCP_INTERNAL_ERROR,
    MCP_HEADER_MISMATCH, MCP_UNSUPPORTED_PROTOCOL_VERSION
using ..Reflection
using ..AutoDoc
using ..Util: text

export register_tool!

# Only the modern, stateless MCP revision is supported in v1.
const PROTOCOL_VERSION = "2026-07-28"
const SUPPORTED_VERSIONS = [PROTOCOL_VERSION]

# Reserved `_meta` keys.
const META_KEY = "_meta"
const META_PROTOCOL = "io.modelcontextprotocol/protocolVersion"
const META_CLIENT_INFO = "io.modelcontextprotocol/clientInfo"
const META_CLIENT_CAPABILITIES = "io.modelcontextprotocol/clientCapabilities"
const META_SERVER_INFO = "io.modelcontextprotocol/serverInfo"

# Default cache hints for list/discovery results (SEP-2549).
const DISCOVER_TTL_MS = 3_600_000
const LIST_TTL_MS = 300_000

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
        "resultType" => "complete",
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
        return text_result(JSON.json(value), value)
    end
end

function toolerror_result(error)::Dict{String,Any}
    return Dict{String,Any}(
        "resultType" => "complete",
        "content" => [Dict{String,Any}("type" => "text", "text" => sprint(showerror, error))],
        "isError" => true,
    )
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

function decode_header_value(value::String)::String
    prefix = "=?base64?"
    suffix = "?="
    if startswith(value, prefix) && endswith(value, suffix) && length(value) >= length(prefix) + length(suffix)
        encoded = value[(length(prefix) + 1):(end - length(suffix))]
        try
            return String(base64decode(encoded))
        catch
            return value
        end
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

function validate_request(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, method::String, params)
    meta = get(params, META_KEY, Dict{String,Any}())
    meta isa AbstractDict || (meta = Dict{String,Any}())

    body_version = get(meta, META_PROTOCOL, nothing)

    if req === nothing
        # stdio: request metadata is carried inline in the body, there is no header layer
        if isnothing(body_version)
            throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_PROTOCOL"))
        end
    else
        header_version = HTTP.header(req, "MCP-Protocol-Version", nothing)

        if isnothing(header_version) || isempty(header_version)
            throw(MCPRequestError(MCP_HEADER_MISMATCH, "Missing required MCP-Protocol-Version header"))
        end
        if isnothing(body_version)
            throw(MCPRequestError(MCP_HEADER_MISMATCH, "Missing required $META_PROTOCOL in _meta"))
        end
        if String(header_version) != String(body_version)
            throw(MCPRequestError(MCP_HEADER_MISMATCH, "Header mismatch: MCP-Protocol-Version header value '$header_version' does not match body value '$body_version'"))
        end
    end

    if String(body_version) != PROTOCOL_VERSION
        throw(MCPRequestError(MCP_UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version", Dict{String,Any}(
            "supported" => copy(SUPPORTED_VERSIONS),
            "requested" => String(body_version),
        )))
    end

    if !haskey(meta, META_CLIENT_CAPABILITIES)
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_CLIENT_CAPABILITIES"))
    end

    # The remaining checks are specific to the Streamable HTTP transport.
    if req === nothing
        return nothing
    end

    header_method = HTTP.header(req, "Mcp-Method", nothing)
    if isnothing(header_method) || isempty(header_method)
        throw(MCPRequestError(MCP_HEADER_MISMATCH, "Missing required Mcp-Method header"))
    end
    if String(header_method) != method
        throw(MCPRequestError(MCP_HEADER_MISMATCH, "Header mismatch: Mcp-Method header value '$header_method' does not match body value '$method'"))
    end

    if method == "tools/call"
        header_name = HTTP.header(req, "Mcp-Name", nothing)
        if isnothing(header_name) || isempty(header_name)
            throw(MCPRequestError(MCP_HEADER_MISMATCH, "Missing required Mcp-Name header"))
        end
        decoded = decode_header_value(String(header_name))
        body_name = get(params, "name", nothing)
        if isnothing(body_name) || decoded != String(body_name)
            throw(MCPRequestError(MCP_HEADER_MISMATCH, "Header mismatch: Mcp-Name header value '$decoded' does not match body value '$(body_name)'"))
        end
    end

    return nothing
end

# ----------------------------------------------------------------------------
# Methods
# ----------------------------------------------------------------------------

function discover_result(ctx::ServerContext)::Dict{String,Any}
    result = Dict{String,Any}(
        "resultType" => "complete",
        "supportedVersions" => copy(SUPPORTED_VERSIONS),
        "capabilities" => Dict{String,Any}("tools" => Dict{String,Any}()),
        META_KEY => Dict{String,Any}(META_SERVER_INFO => Dict{String,Any}(
            "name" => ctx.mcp.server_name,
            "version" => ctx.mcp.server_version,
        )),
        "ttlMs" => DISCOVER_TTL_MS,
        "cacheScope" => "public",
    )
    if !isnothing(ctx.mcp.instructions)
        result["instructions"] = ctx.mcp.instructions
    end
    return result
end

function tools_list(ctx::ServerContext)::Dict{String,Any}
    tools = Dict{String,Any}[]
    for name in sort(collect(keys(ctx.mcp.tools)))
        tool = ctx.mcp.tools[name]
        push!(tools, Dict{String,Any}(
            "name" => tool.name,
            "description" => tool.description,
            "inputSchema" => inputschema(tool),
        ))
    end
    return Dict{String,Any}(
        "resultType" => "complete",
        "tools" => tools,
        "ttlMs" => LIST_TTL_MS,
        "cacheScope" => "public",
    )
end

function call_tool(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params)::Tuple{Dict{String,Any},Int}
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
        return result_body(id, toolresult(value)), 200
    catch error
        if error isa MCPRequestError
            return error_body(id, error.code, error.message, error.data), 200
        end
        return result_body(id, toolerror_result(error)), 200
    end
end

# Transport agnostic dispatch. Returns the JSON-RPC response body together with
# the HTTP status code that should be used for it (stdio ignores the status).
function dispatch(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, method::String, payload)::Tuple{Dict{String,Any},Int}
    if method == "server/discover"
        return result_body(id, discover_result(ctx)), 200
    elseif method == "tools/list"
        return result_body(id, tools_list(ctx)), 200
    elseif method == "tools/call"
        params = get(payload, "params", Dict{String,Any}())
        params isa AbstractDict || (params = Dict{String,Any}())
        return call_tool(ctx, req, id, params)
    elseif method == "ping"
        return result_body(id, Dict{String,Any}("resultType" => "complete")), 200
    else
        return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
    end
end

# ----------------------------------------------------------------------------
# Entry points
# ----------------------------------------------------------------------------

# Handle a single parsed JSON-RPC message. Returns `(body, status)`, where
# `body` is `nothing` for notifications (no response is written).
function process(ctx::ServerContext, payload, req::Union{Nothing,HTTP.Request})::Tuple{Union{Nothing,Dict{String,Any}},Int}
    if !(payload isa AbstractDict)
        return error_body(nothing, MCP_INVALID_REQUEST, "Invalid Request"), 400
    end

    method = get(payload, "method", nothing)
    has_id = haskey(payload, "id") && !isnothing(payload["id"])

    # Notifications (no id) are accepted without a response.
    if !has_id
        return nothing, 202
    end

    id = payload["id"]

    if !(method isa AbstractString)
        return error_body(id, MCP_INVALID_REQUEST, "Invalid Request"), 400
    end

    params = get(payload, "params", Dict{String,Any}())
    params isa AbstractDict || (params = Dict{String,Any}())

    try
        validate_request(ctx, req, String(method), params)
    catch error
        if error isa MCPRequestError
            return error_body(id, error.code, error.message, error.data), 400
        end
        rethrow()
    end

    return dispatch(ctx, req, id, String(method), payload)
end

"""
    handle(ctx::ServerContext, req::HTTP.Request) :: HTTP.Response

Streamable HTTP transport entry point. Handles a single JSON-RPC request or
notification over a stateless POST.
"""
function handle(ctx::ServerContext, req::HTTP.Request)::HTTP.Response
    origin_response = check_origin(ctx, req)
    isnothing(origin_response) || return origin_response

    payload = try
        JSON.parse(String(req.body))
    catch
        return json_response(error_body(nothing, MCP_PARSE_ERROR, "Parse error"); status=400)
    end

    body, status = process(ctx, payload, req)
    return isnothing(body) ? HTTP.Response(status) : json_response(body; status=status)
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
