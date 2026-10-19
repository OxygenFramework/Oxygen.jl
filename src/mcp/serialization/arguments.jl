# Argument coercion, resolution, and handler invocation for tools and prompts.
# Included into `MCP.Serialization` by `../serialization.jl`.

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
        return Reflection.parse_enum(target, value)
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
# Registry lookup
# ----------------------------------------------------------------------------

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
