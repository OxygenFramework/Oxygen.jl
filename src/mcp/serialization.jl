# Schema generation, argument coercion/resolution, content blocks, result
# envelopes, and JSON-RPC body helpers. Included into the `MCP` module by
# `../mcp.jl`.

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
# Argument resolution / handler invocation (shared by tools and prompts)
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

function invoke_registered(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, handler::Function,
                           params::Vector{MCPParam}, argnames::Vector{Symbol},
                           has_context::Bool, has_request::Bool, arguments)
    pos_values = Any[]
    kwpairs = Pair{Symbol,Any}[]

    for p in params
        if p.param.name in argnames
            resolve_argument!(pos_values, p, arguments)
        else
            resolve_kwarg!(kwpairs, p, arguments)
        end
    end

    has_context && push!(kwpairs, :context => getappcontext(ctx))
    has_request && push!(kwpairs, :request => req)

    return handler(pos_values...; kwpairs...)
end

# ----------------------------------------------------------------------------
# Content serialization (shared by tools and prompts)
# ----------------------------------------------------------------------------

# The content block types a handler may return pre-shaped (they pass through).
const MCP_CONTENT_TYPES = ("text", "image", "audio", "resource_link", "resource")

# MIME types carried in a `text` content block even without a `text/` prefix.
function is_text_mime(mime::AbstractString)::Bool
    m = lowercase(mime)
    return startswith(m, "text/") ||
           m in ("application/json", "application/xml", "application/javascript") ||
           endswith(m, "+json") || endswith(m, "+xml")
end

# The media type of an `HTTP.Response`, with any parameters (`; charset=...`) dropped.
function response_mime(resp::HTTP.Response)::String
    header = HTTP.header(resp, "Content-Type", "application/octet-stream")
    return lowercase(strip(split(String(header), ';')[1]))
end

text_block(content)::Dict{String,Any} =
    Dict{String,Any}("type" => "text", "text" => string(content))

"""
    binary_block(bytes, mime) :: Dict

Serialize raw bytes into the MCP content block that best fits `mime`: an `image`
or `audio` block (base64 `data`), a `text` block for textual media, or an
embedded `resource` (base64 `blob`) for any other binary, since MCP has no bare
binary content block.
"""
function binary_block(bytes::Vector{UInt8}, mime::String)::Dict{String,Any}
    mime = String(strip(split(mime, ';')[1]))
    m = lowercase(mime)
    if startswith(m, "image/")
        return Dict{String,Any}("type" => "image", "data" => base64encode(bytes), "mimeType" => mime)
    elseif startswith(m, "audio/")
        return Dict{String,Any}("type" => "audio", "data" => base64encode(bytes), "mimeType" => mime)
    elseif is_text_mime(m)
        return text_block(String(bytes))
    else
        return Dict{String,Any}(
            "type" => "resource",
            "resource" => Dict{String,Any}(
                "uri" => "oxygen://blob",
                "mimeType" => mime,
                "blob" => base64encode(bytes),
            ),
        )
    end
end

response_block(resp::HTTP.Response)::Dict{String,Any} =
    binary_block(response_bytes(resp), response_mime(resp))

"""
    content_block(value) :: Dict

Serialize a handler return value into a single MCP content block. `HTTP.Response`
values honor their `Content-Type` (so `html`/`json`/`text`/`binary`/`file` produce
`text` blocks and image/audio responses produce base64 media blocks); a dict
carrying a known content `type` passes through; anything else is JSON-encoded
into a text block.
"""
function content_block(value)::Dict{String,Any}
    if value isa HTTP.Response
        return response_block(value)
    elseif value isa AbstractString
        return text_block(String(value))
    elseif value isa AbstractVector{UInt8}
        return binary_block(value, HTTP.sniff(value))
    elseif value isa AbstractDict && get(value, "type", nothing) in MCP_CONTENT_TYPES
        return value
    else
        return text_block(JSON.json(value))
    end
end

function content_result(block::Dict{String,Any}, structured_content=nothing)::Dict{String,Any}
    result = Dict{String,Any}(
        "content" => Any[block],
        "isError" => false,
    )
    structured_content === nothing || (result["structuredContent"] = structured_content)
    return result
end

function toolresult(value)::Dict{String,Any}
    if value isa HTTP.Response || value isa AbstractString ||
       value isa AbstractVector{UInt8} ||
       (value isa AbstractDict && get(value, "type", nothing) in MCP_CONTENT_TYPES)
        return content_result(content_block(value))
    else
        encoded = JSON.json(value)
        # CallToolResult.structuredContent MUST be a JSON object per the MCP
        # spec; a scalar or array result has no valid structured form, so it is
        # omitted (the JSON still travels as text content).
        structured = startswith(lstrip(encoded), "{") ? JSON.parse(encoded) : nothing
        return content_result(text_block(encoded), structured)
    end
end

# ----------------------------------------------------------------------------
# Result envelope
# ----------------------------------------------------------------------------

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
