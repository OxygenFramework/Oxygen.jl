# Tool registration and the `tools/list` / `tools/call` methods.
# Included into the `MCP` module by `../mcp.jl`.

# ----------------------------------------------------------------------------
# Registration (the only write path to the registry)
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

function invoke_tool(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, tool::MCPTool, arguments)
    return invoke_registered(ctx, req, tool.handler, tool.params, tool.argnames,
                             tool.has_context, tool.has_request, arguments)
end

# ----------------------------------------------------------------------------
# Methods
# ----------------------------------------------------------------------------

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
