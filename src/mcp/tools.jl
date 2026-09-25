# Tool registration and the `tools/list` / `tools/call` methods.
# Included into the `MCP` module by `../mcp.jl`.

# ----------------------------------------------------------------------------
# Registration (the only write path to the registry)
# ----------------------------------------------------------------------------

# Reflect a handler into its positional argument names and `MCPParam`s. The
# explicit `descriptions`/`names` maps override the reflected values, and
# `skip_first` drops the leading positional handler argument (the HTTP request /
# stream / websocket injected by the routing layer for route-backed tools).
function reflect_mcp_params(func::Function, descriptions::Dict{Symbol,String},
                            names::Dict{Symbol,String}; skip_first::Bool=false)
    info = Reflection.splitdef(func; start=1)

    positional = info.args
    if skip_first && !isempty(info.args)
        positional = info.args[2:end]
    end

    argnames = Symbol[]
    mcp_params = MCPParam[]

    for p in positional
        if p.name in (:context, :request)
            continue
        end
        push!(argnames, p.name)
        push!(mcp_params, MCPParam(p, get(descriptions, p.name, ""), get(names, p.name, string(p.name))))
    end

    for p in info.kwargs
        # `context` / `request` are injected by the framework, never part of the schema
        if p.name in (:context, :request)
            continue
        end
        push!(mcp_params, MCPParam(p, get(descriptions, p.name, ""), get(names, p.name, string(p.name))))
    end

    return info, argnames, mcp_params
end

# The set of handler parameters a client may supply: every reflected positional
# and keyword parameter except the framework-injected `context`/`request`. For
# route-backed tools the leading positional argument (the injected request) is
# dropped too.
function mcp_param_names(func::Function; skip_first::Bool=false)::Set{Symbol}
    info = Reflection.splitdef(func; start=1)

    positional = info.args
    if skip_first && !isempty(info.args)
        positional = info.args[2:end]
    end

    names = Set{Symbol}()
    for p in positional
        p.name in (:context, :request) && continue
        push!(names, p.name)
    end
    for p in info.kwargs
        p.name in (:context, :request) && continue
        push!(names, p.name)
    end
    return names
end

# Guard against mistyped parameter metadata: every key in `descriptions`/`names`
# must name a real handler parameter, and when `require_complete` is set every
# handler parameter must carry a description. Throws `ArgumentError` otherwise.
function validate_mcp_param_keys(func::Function, descriptions::Dict{Symbol,String},
                                 names::Dict{Symbol,String}; skip_first::Bool=false,
                                 require_complete::Bool=false)
    allowed = mcp_param_names(func; skip_first=skip_first)

    # Metadata keys that don't name a real handler parameter (mistyped or extra)
    unknown = sort!(collect(setdiff(union(keys(descriptions), keys(names)), allowed)))

    isempty(unknown) || throw(ArgumentError(
        "Unknown MCP parameter name(s): $(join(string.(unknown), ", ")). " *
        "Expected one of: $(join(string.(sort!(collect(allowed))), ", "))"))

    if require_complete
        missing = sort!(collect(setdiff(allowed, keys(descriptions))))
        isempty(missing) || throw(ArgumentError(
            "Missing description for MCP parameter(s): $(join(string.(missing), ", "))"))
    end
    return nothing
end

# Whether the handler declares an injected `context` / `request` keyword.
function injected_kwargs(func::Function)
    kwdecl = Base.kwarg_decl(first(methods(func)))
    return (:context in kwdecl, :request in kwdecl)
end

# Extract a handler's docstring, if one was attached to its binding. Returns an
# empty string for anonymous functions or undocumented handlers.
function function_docstring(func::Function)::String
    try
        mod = parentmodule(func)
        binding = Base.Docs.Binding(mod, nameof(func))
        entry = get(Base.Docs.meta(mod), binding, nothing)
        if entry === nothing
            return ""
        end
        if entry isa Base.Docs.MultiDoc
            texts = String[]
            for docstr in values(entry.docs)
                text = strip(join(docstr.text, "\n"))
                isempty(text) || push!(texts, text)
            end
            isempty(texts) && return ""
            # Multiple methods may each carry a docstring; pick deterministically.
            sort!(texts)
            return first(texts)
        elseif entry isa Base.Docs.DocStr
            return strip(join(entry.text, "\n"))
        end
    catch
    end
    return ""
end

"""
    register_tool!(ctx::ServerContext, desc, params, func::Function; name=nothing)

Reflect on `func`, merge the explicit `params` descriptions, and store the
resulting `MCPTool` in `ctx.mcp.tools` keyed by its wire name.

`params` accepts the same forms as route-level MCP metadata: a `Dict` or
`NamedTuple` (Symbol keys only), or a vector of `Pair`s. Each value is the
parameter's description. Every handler parameter must be described and every key
must name a real parameter, otherwise an `ArgumentError` is thrown. Wire names
default to the Julia parameter name.
"""
function register_tool!(ctx::ServerContext, desc, params, func::Function; name=nothing)
    descriptions = parse_mcp_parameters(params)
    validate_mcp_param_keys(func, descriptions, Dict{Symbol,String}(); require_complete=true)
    info, argnames, mcp_params = reflect_mcp_params(func, descriptions, Dict{Symbol,String}())
    has_context, has_request = injected_kwargs(func)

    wirename = isnothing(name) ? string(info.name) : string(name)
    store_tool!(ctx, wirename, string(desc), func, mcp_params, argnames,
                has_context, has_request, false)
end

"""
    register_route_tool!(ctx::ServerContext, config::MCPConfig, func::Function;
                         httpmethod::String="", route::String="")

Expose an HTTP route handler as an MCP tool using the resolved router/route
metadata. The handler's leading positional argument (the injected
`HTTP.Request`) is dropped from the schema and re-injected at call time, and the
router description is used as a group prefix for the tool description. The
tool's wire name defaults to the handler's name (endpoint-specific) unless the
route metadata supplies `name`.
"""
function register_route_tool!(ctx::ServerContext, config::MCPConfig, func::Function;
                              httpmethod::String="", route::String="")
    info, argnames, mcp_params = reflect_mcp_params(func, config.parameters, config.names;
                                                    skip_first=true)
    has_context, has_request = injected_kwargs(func)
    inject_request = !isempty(info.args)

    own = !isempty(config.description) ? config.description : function_docstring(func)
    description = if !isempty(config.group) && !isempty(own)
        "$(config.group): $own"
    elseif !isempty(own)
        own
    else
        config.group
    end

    wirename = if !isnothing(config.toolname)
        string(config.toolname)
    elseif !Base.isgensym(info.name)
        string(info.name)
    else
        # Anonymous/do-block handlers have no usable name; derive one from the
        # endpoint so it stays specific and collision-free.
        derived_tool_name(httpmethod, route)
    end

    # An explicit name (route `name = ...` or a named handler) must be unique. An
    # endpoint-derived name is disambiguated instead, so two anonymous handlers
    # that slug to the same text can still coexist.
    explicit = !isnothing(config.toolname) || !Base.isgensym(info.name)

    # One handler mounted on several methods yields one tool; re-registering the
    # same function is a no-op, anything else is a collision.
    existing = get(ctx.mcp.tools, wirename, nothing)
    if !isnothing(existing)
        if existing.handler === func
            return existing
        end
        if explicit
            throw(ArgumentError("An MCP tool named `$wirename` is already registered"))
        end
        base = wirename
        suffix = 2
        while haskey(ctx.mcp.tools, wirename)
            wirename = "$(base)_$(suffix)"
            suffix += 1
        end
    end

    store_tool!(ctx, wirename, description, func, mcp_params, argnames,
                has_context, has_request, inject_request)
end

# Build a stable, endpoint-specific tool name for an anonymous handler.
function derived_tool_name(httpmethod::String, route::String)::String
    slug = strip(replace(route, r"[^A-Za-z0-9]+" => "_"), '_')
    if isempty(slug)
        slug = "tool"
    end
    method = isempty(httpmethod) ? "" : lowercase(httpmethod) * "_"
    return method * slug
end

# Shared registry write. A wire name may only be claimed once.
function store_tool!(ctx::ServerContext, wirename::String, description::String, func::Function,
                     mcp_params::Vector{MCPParam}, argnames::Vector{Symbol},
                     has_context::Bool, has_request::Bool, inject_request::Bool)
    if haskey(ctx.mcp.tools, wirename)
        throw(ArgumentError("An MCP tool named `$wirename` is already registered"))
    end

    tool = MCPTool(wirename, description, func, mcp_params, argnames,
                   has_context, has_request, inject_request)
    ctx.mcp.tools[wirename] = tool
    return tool
end

function invoke_tool(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, tool::MCPTool, arguments)
    return invoke_registered(ctx, req, tool.handler, tool.params, tool.argnames,
                             tool.has_context, tool.has_request, arguments;
                             inject_request=tool.inject_request)
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
