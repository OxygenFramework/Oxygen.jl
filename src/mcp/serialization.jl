# Schema generation, argument coercion/resolution, content blocks, result
# envelopes, and JSON-RPC body helpers. Included into the `MCP` module by
# `../mcp.jl`.

# ----------------------------------------------------------------------------
# Shared helpers
# ----------------------------------------------------------------------------

# Copy any keyed container (`Dict`, `NamedTuple`, ...) into a `Dict{String,Any}`
# with stringified keys. The MCP wire layer accepts symbol- and string-keyed
# input uniformly, so validation and serialization normalize through here.
string_keyed(entries)::Dict{String,Any} =
    Dict{String,Any}(String(key) => value for (key, value) in pairs(entries))

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
    if nullable
        schema["nullable"] = true
    end
    return schema, defs
end

function _typeschema(T::Type, defs::Dict{String,Any})
    T = AutoDoc.unwrap_type(T)

    if T isa Union
        return _unionschema(T, defs)
    elseif AutoDoc.is_custom_struct(T)
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
    elseif T <: AbstractDict
        schema = Dict{String,Any}("type" => "object")
        value_type = Reflection.dict_valtype(T)
        if value_type !== Any
            value_schema, value_defs = typeschema(value_type)
            merge!(defs, value_defs)
            schema["additionalProperties"] = value_schema
        end
        return schema
    else
        schema = Dict{String,Any}("type" => AutoDoc.gettype(T))
        format = AutoDoc.getformat(T)
        if !isnothing(format)
            schema["format"] = format
        end
        if T <: Enum
            schema["enum"] = collect(Int.(Base.Enums.instances(T)))
        end
        return schema
    end
end

# Schema for a Union type: one member keeps its schema (marked `nullable` when
# the union admits Nothing/Missing), several members become `anyOf`.
function _unionschema(T::Union, defs::Dict{String,Any})
    members = Dict{String,Any}[]
    nullable = false

    for member in Base.uniontypes(T)
        if member === Nothing || member === Missing
            nullable = true
        else
            push!(members, _typeschema(member, defs))
        end
    end

    if isempty(members)
        return Dict{String,Any}()
    end
    schema = length(members) == 1 ? members[1] : Dict{String,Any}("anyOf" => members)
    if nullable
        schema["nullable"] = true
    end
    return schema
end

function paramschema(p::MCPParam)
    schema, defs = typeschema(p.param.type)
    if !isempty(p.description)
        schema["description"] = p.description
    end
    if p.param.hasdefault
        schema["default"] = p.param.default
    end
    return schema, defs
end

"""
    inputschema(tool::MCPTool) :: Dict

The JSON Schema describing a tool's expected arguments. Built once at
registration (see `inputschema(::Vector{MCPParam})`) and cached on the tool: the
schema cannot change after registration, and regenerating it means re-reflecting
every custom struct parameter on every `tools/list`.
"""
inputschema(tool::MCPTool)::Dict{String,Any} = tool.input_schema

function inputschema(params::Vector{MCPParam})::Dict{String,Any}
    if isempty(params)
        return Dict{String,Any}("type" => "object", "additionalProperties" => false)
    end

    properties = Dict{String,Any}()
    required = String[]
    defs = Dict{String,Any}()

    for p in params
        name = p.wirename
        schema, pdefs = paramschema(p)
        properties[name] = schema
        merge!(defs, pdefs)
        if isrequired(p.param)
            push!(required, name)
        end
    end

    result = Dict{String,Any}("type" => "object", "properties" => properties)
    if !isempty(required)
        result["required"] = required
    end
    if !isempty(defs)
        result["\$defs"] = defs
    end
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

    if isnothing(value)
        return nothing
    end

    if target === Any
        return value
    elseif value isa target
        return value
    elseif target <: AbstractString
        return string(value)
    elseif target <: Integer    # also covers Bool, which is an Integer subtype
        return value isa AbstractString ? parse(target, value) : convert(target, value)
    elseif target <: AbstractFloat
        return value isa AbstractString ? parse(target, value) : convert(target, value)
    elseif target <: Enum
        return target(value isa AbstractString ? parse(Int, value) : Int(value))
    elseif AutoDoc.is_custom_struct(target) && value isa AbstractDict
        return Reflection.struct_builder(target, value)
    elseif target <: AbstractArray && value isa AbstractVector
        return Reflection.parse_array_value(target, value)
    elseif target <: AbstractDict && value isa AbstractDict
        return Reflection.parse_dict_value(target, value)
    elseif target isa Union
        return Reflection.parse_union_value(target, value)
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

# Look up an argument by its MCP wire name, falling back to the Julia parameter
# name (and its String form) so clients that send the reflected name still work.
function argument_value(arguments, p::MCPParam)
    wirename = p.wirename
    if haskey(arguments, wirename)
        return (true, arguments[wirename])
    end

    name = p.param.name
    if haskey(arguments, name)
        return (true, arguments[name])
    end

    stringname = string(name)
    if haskey(arguments, stringname)
        return (true, arguments[stringname])
    end

    return (false, nothing)
end

# Coerce one wire value, translating any coercion failure into a JSON-RPC
# params error. Without this, a bad client-supplied value (e.g. a URI capture
# that does not parse as Int) escapes as a raw exception and is reported as an
# internal error instead of `-32602`.
function coerce_argument(p::MCPParam, value)
    try
        return parse_tool_argument(p.param.type, value)
    catch error
        if error isa MCPRequestError
            rethrow()
        end
        throw(MCPRequestError(MCP_INVALID_PARAMS,
            "Invalid value for argument `$(p.wirename)`: $(sprint(showerror, error))"))
    end
end

# The value to bind to a parameter: the coerced wire value when supplied, else
# the declared default, else a `-32602` params error.
function resolved_value(p::MCPParam, arguments)
    found, value = argument_value(arguments, p)
    if found
        return coerce_argument(p, value)
    end
    if p.param.hasdefault
        return p.param.default
    end
    throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required argument: $(p.wirename)"))
end

"""
    resolve_registered(ctx, req, params, argnames, has_context, has_request, arguments;
                       inject_request=false, has_stream=false, stream=nothing)

Resolve the wire arguments into the positional values and keyword pairs that
invoke the handler. Kept separate from the invocation so a streaming call can
surface argument-validation errors before its producer task starts.
"""
function resolve_registered(ctx::ServerContext, req::Union{Nothing,HTTP.Request},
                            params::Vector{MCPParam}, argnames::Vector{Symbol},
                            has_context::Bool, has_request::Bool, arguments;
                            inject_request::Bool=false, has_stream::Bool=false, stream=nothing)
    pos_values = Any[]
    kwpairs = Pair{Symbol,Any}[]

    # Route-backed tools declare the injected request as their leading positional
    # argument; provide it here so the shared invocation path can call them.
    if inject_request
        push!(pos_values, req)
    end

    for p in params
        value = resolved_value(p, arguments)
        if p.param.name in argnames
            push!(pos_values, value)
        else
            push!(kwpairs, p.param.name => value)
        end
    end

    if has_context
        push!(kwpairs, :context => getappcontext(ctx))
    end
    
    if has_request
        push!(kwpairs, :request => req)
    end

    if has_stream
        push!(kwpairs, :stream => stream)
    end

    return pos_values, kwpairs
end

function invoke_registered(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, handler::Function,
                           params::Vector{MCPParam}, argnames::Vector{Symbol},
                           has_context::Bool, has_request::Bool, arguments;
                           inject_request::Bool=false, has_stream::Bool=false, stream=nothing)
    pos_values, kwpairs = resolve_registered(ctx, req, params, argnames,
                                             has_context, has_request, arguments;
                                             inject_request=inject_request,
                                             has_stream=has_stream, stream=stream)
    return handler(pos_values...; kwpairs...)
end

# Node-based entry points: dispatch on the registered component once instead of
# threading its fields through every call site.
function resolve_registered(ctx::ServerContext, req::Union{Nothing,HTTP.Request},
                            node::MCPCallable, arguments; kwargs...)
    return resolve_registered(ctx, req, node.params, node.argnames, node.has_context,
                              node.has_request, arguments; kwargs...)
end

function invoke_registered(ctx::ServerContext, req::Union{Nothing,HTTP.Request},
                           node::MCPCallable, arguments; kwargs...)
    return invoke_registered(ctx, req, node.handler, node.params, node.argnames,
                             node.has_context, node.has_request, arguments; kwargs...)
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
           m in ("application/json", "application/xml", "application/javascript",
                 "application/toml", "application/yaml", "application/x-yaml") ||
           endswith(m, "+json") || endswith(m, "+xml")
end

# The media type of an `HTTP.Response`, with any parameters (`; charset=...`) dropped.
function response_mime(resp::HTTP.Response)::String
    header = HTTP.header(resp, "Content-Type", "application/octet-stream")
    return lowercase(strip(split(String(header), ';')[1]))
end

text_block(content)::Dict{String,Any} = Dict{String,Any}("type" => "text", "text" => string(content))

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
    kind = startswith(m, "image/") ? "image" : startswith(m, "audio/") ? "audio" : nothing
    if !isnothing(kind)
        return Dict{String,Any}("type" => kind, "data" => base64encode(bytes), "mimeType" => mime)
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
content_block(value::HTTP.Response) :: Dict{String,Any} = response_block(value)
content_block(value::AbstractString) :: Dict{String,Any} = text_block(String(value))
content_block(value::AbstractVector{UInt8}) :: Dict{String,Any} = binary_block(value, HTTP.sniff(value))

# Dispatch is by type, not value, so the "known content type" test has to stay
# inside the `AbstractDict` method; a plain dict falls back to JSON text here
# because the `Any` method below can never be more specific than this one.
function content_block(value::AbstractDict) :: Dict{String,Any}
    if get(value, "type", nothing) in MCP_CONTENT_TYPES 
        return value
    end
    return text_block(JSON.json(value))
end

# Default case: anything not matched above is JSON-encoded into a text block.
content_block(value::Any) :: Dict{String,Any} = text_block(JSON.json(value))

function content_result(block::Dict{String,Any}, structured_content=nothing)::Dict{String,Any}
    result = Dict{String,Any}(
        "content" => Any[block],
        "isError" => false,
    )
    if !isnothing(structured_content)
        result["structuredContent"] = structured_content
    end
    return result
end

function toolresult(value; structured::Bool=true)::Dict{String,Any}
    if value isa HTTP.Response || 
        value isa AbstractString ||
        value isa AbstractVector{UInt8} ||
        (value isa AbstractDict && get(value, "type", nothing) in MCP_CONTENT_TYPES)
        return content_result(content_block(value))
    else
        encoded = JSON.json(value)
        # CallToolResult.structuredContent MUST be a JSON object per the MCP
        # spec; a scalar or array result has no valid structured form, so it is
        # omitted (the JSON still travels as text content). Revisions that do
        # not emit structuredContent skip the decode entirely.
        parsed = structured && startswith(lstrip(encoded), "{") ? JSON.parse(encoded) : nothing
        return content_result(text_block(encoded), parsed)
    end
end

"""
    tool_success_result(value; spec) :: Dict

The result of a completed tool call: the handler's return value serialized into
content blocks, with `structuredContent` emitted only for revisions that
introduced it (2025-06-18+). Shared by the buffered and streamed `tools/call`
paths so both produce identical bytes.
"""
function tool_success_result(value; spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    return toolresult(value; structured=emits_structured_content(spec))
end

"""
    resolve_registered_node(registry, id, params, label) :: (node, arguments) or (nothing, response)

Look up the component named by the request `params` in `registry` and read its
`arguments` object. On a missing/unknown name or a malformed arguments value,
returns `(nothing, response)` where `response` is the `(error_body, 200)` tuple
the caller should return. Shared by `tools/call` and `prompts/get`.
"""
function resolve_registered_node(registry, id, params, label::String)
    body_name = get(params, "name", nothing)
    if isnothing(body_name)
        return nothing, (error_body(id, MCP_INVALID_PARAMS, "Missing $label name"), 200)
    end

    wirename = String(body_name)
    node = get(registry, wirename, nothing)
    if isnothing(node)
        return nothing, (error_body(id, MCP_INVALID_PARAMS, "Unknown $label: $wirename"), 200)
    end

    arguments = get(params, "arguments", Dict{String,Any}())
    if isnothing(arguments)
        arguments = Dict{String,Any}()
    end
    if !(arguments isa AbstractDict)
        return nothing, (error_body(id, MCP_INVALID_PARAMS, "Invalid arguments: expected an object"), 200)
    end

    return node, arguments
end

# ----------------------------------------------------------------------------
# Result envelope
# ----------------------------------------------------------------------------

"""
    list_result(key, items; spec) :: Dict

Build a `*/list` result under `key` through the revision's result strategy: the
modern revision adds cache hints, legacy revisions leave the result untouched.
"""
function list_result(key::String, items::Vector{Dict{String,Any}};
                     spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    return with_cache_hints(spec, Dict{String,Any}(key => items))
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
    if !(meta isa AbstractDict)
        meta = Dict{String,Any}()
    end
    meta[META_SERVER_INFO] = Dict{String,Any}(
        "name" => ctx.mcp.server_name[],
        "version" => ctx.mcp.server_version[],
    )
    result[META_KEY] = meta
    return result
end

# ----------------------------------------------------------------------------
# JSON-RPC response helpers
# ----------------------------------------------------------------------------

# JSON-RPC response helper used by the buffered and streamed result paths
# alike. Transport-specific writers live in `../mcp.jl`.
function result_body(id, result)::Dict{String,Any}
    return Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "result" => result)
end

"""
    result_response(ctx, id, result; spec) :: (body, status)

Shape `result` through the revision's envelope (a no-op for legacy revisions)
and wrap it in its JSON-RPC body. The single place the envelope is applied to
successful results.
"""
function result_response(ctx::ServerContext, id, result::Dict{String,Any};
                         spec::Val=LATEST_LEGACY_SPEC)::Tuple{Dict{String,Any},Int}
    return result_body(id, result_envelope(spec, ctx, result)), 200
end

"""
    request_error_body(id, error, code) :: Dict

The JSON-RPC error body for a thrown `MCPRequestError`, normally using the
error's own code. `read_resource` overrides the code to translate the legacy
not-found error by era.
"""
function request_error_body(id, error::MCPRequestError, code::Int=error.code)::Dict{String,Any}
    return error_body(id, code, error.message, error.data)
end
