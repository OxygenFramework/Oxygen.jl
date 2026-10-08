# Tool registration and the `tools/list` / `tools/call` methods.
# Included into the `MCP` module by `../mcp.jl`.

# ----------------------------------------------------------------------------
# Registration (the only write path to the registry)
# ----------------------------------------------------------------------------

# The framework-injected handler parameters. They are never part of a schema;
# `context`/`request` are injected as keywords, while `stream` is the Surface A
# entry point (the framework creates the channel, injects it, and routes the
# call through the streaming path).
const INJECTED_PARAMS = (:context, :request, :stream)

# The compiler-generated name Julia reflects for an unnamed argument. It has no
# usable wire name, so registration rejects it. Checked after `skip_first` drops
# the route's leading request argument, which is allowed to be unnamed.
const UNNAMED_PARAM = Symbol("#unused#")

"""
    HandlerSignature

The reflected view of a handler: `info` is the `splitdef` result, `argnames`
are the positional parameter names included in schemas (in order), `params`
are the positional-then-keyword `MCPParam`s (injected names dropped), and the
flags say which injected keywords the handler declares.
"""
struct HandlerSignature
    info        :: NamedTuple
    argnames    :: Vector{Symbol}
    params      :: Vector{MCPParam}
    has_context :: Bool
    has_request :: Bool
    has_stream  :: Bool
end

mcp_param(p, descriptions, names) =
    MCPParam(p, get(descriptions, p.name, ""), get(names, p.name, string(p.name)))

# Single reflection walk shared by tools, prompts, and resources. The explicit
# `descriptions`/`names` maps override the reflected values, and `skip_first`
# drops the leading positional handler argument (the HTTP request / stream /
# websocket injected by the routing layer for route-backed tools).
function reflect_handler(func::Function;
                         descriptions::Dict{Symbol,String}=Dict{Symbol,String}(),
                         names::Dict{Symbol,String}=Dict{Symbol,String}(),
                         skip_first::Bool=false)::HandlerSignature
    info = Reflection.splitdef(func; start=1)

    positional = info.args
    if skip_first && !isempty(info.args)
        positional = info.args[2:end]
    end

    argnames = Symbol[]
    mcp_params = MCPParam[]
    for p in positional
        if p.name in INJECTED_PARAMS
            continue
        end
        if p.name === UNNAMED_PARAM
            throw(ArgumentError(
                "MCP handlers cannot declare unnamed parameters; " *
                "give the `::$(p.type)` parameter a name"))
        end
        push!(argnames, p.name)
        push!(mcp_params, mcp_param(p, descriptions, names))
    end
    for p in info.kwargs
        if p.name in INJECTED_PARAMS
            continue
        end
        push!(mcp_params, mcp_param(p, descriptions, names))
    end

    kwdecl = Tuple(p.name for p in info.kwargs)
    return HandlerSignature(info, argnames, mcp_params,
                            :context in kwdecl, :request in kwdecl, :stream in kwdecl)
end

# Guard against mistyped parameter metadata: every key in `descriptions`/`names`
# must name a real handler parameter, and when `require_complete` is set every
# handler parameter must carry a description. Throws `ArgumentError` otherwise.
function validate_mcp_param_keys(func::Function, descriptions::Dict{Symbol,String},
                                 names::Dict{Symbol,String}; skip_first::Bool=false,
                                 require_complete::Bool=false)
    return validate_mcp_param_keys(reflect_handler(func; skip_first=skip_first),
                                   descriptions, names; require_complete=require_complete)
end

function validate_mcp_param_keys(signature::HandlerSignature, descriptions::Dict{Symbol,String},
                                 names::Dict{Symbol,String}; require_complete::Bool=false)
    allowed = Set(p.param.name for p in signature.params)

    # Metadata keys that don't name a real handler parameter (mistyped or extra)
    unknown = sort!(collect(setdiff(union(keys(descriptions), keys(names)), allowed)))

    if !isempty(unknown)
        throw(ArgumentError(
            "Unknown MCP parameter name(s): $(join(string.(unknown), ", ")). " *
            "Expected one of: $(join(string.(sort!(collect(allowed))), ", "))"))
    end

    if require_complete
        missing = sort!(collect(setdiff(allowed, keys(descriptions))))
        if !isempty(missing)
            throw(ArgumentError(
                "Missing description for MCP parameter(s): $(join(string.(missing), ", "))"))
        end
    end
    return nothing
end

# Extract a handler's docstring, if one was attached to its binding. Returns an
# empty string for anonymous functions or undocumented handlers.
function function_docstring(func::Function)::String
    try
        mod = parentmodule(func)
        binding = Base.Docs.Binding(mod, nameof(func))
        entry = get(Base.Docs.meta(mod), binding, nothing)
        if isnothing(entry)
            return ""
        end
        if entry isa Base.Docs.MultiDoc
            texts = String[]
            for docstr in values(entry.docs)
                text = strip(join(docstr.text, "\n"))
                if !isempty(text)
                    push!(texts, text)
                end
            end
            if isempty(texts)
                return ""
            end
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
`NamedTuple` (Symbol keys only), a single `Pair` for the common one-parameter
case, or a vector of `Pair`s. Each value is the parameter's description. Every
handler parameter must be described and every key must name a real parameter,
otherwise an `ArgumentError` is thrown. Wire names default to the Julia
parameter name.

When `desc` is empty the handler's own docstring is used as the tool
description, so the two-argument `@tool`/`tool` forms need not repeat it.
"""
function register_tool!(ctx::ServerContext, desc, params, func::Function; name=nothing)
    descriptions = parse_mcp_parameters(params)
    signature = reflect_handler(func; descriptions=descriptions)
    validate_mcp_param_keys(signature, descriptions, Dict{Symbol,String}(); require_complete=true)

    wirename = isnothing(name) ? string(signature.info.name) : string(name)
    own = string(desc)
    description = isempty(own) ? function_docstring(func) : own
    store_tool!(ctx, wirename, description, func, signature, false)
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
function register_route_tool!(ctx::ServerContext, config::MCPConfig, func::Function; httpmethod::String="", route::String="")
    signature = reflect_handler(func; descriptions=config.parameters, names=config.names, skip_first=true)
    inject_request = !isempty(signature.info.args)

    own = !isempty(config.description) ? config.description : function_docstring(func)
    description = 
        if !isempty(config.group) && !isempty(own)
            "$(config.group): $own"
        elseif !isempty(own)
            own
        else
            config.group
        end

    wirename = 
        if !isnothing(config.toolname)
            string(config.toolname)
        elseif !Base.isgensym(signature.info.name)
            string(signature.info.name)
        else
            # Anonymous/do-block handlers have no usable name; derive one from the
            # endpoint so it stays specific and collision-free.
            derived_tool_name(httpmethod, route)
        end

    # An explicit name (route `name = ...` or a named handler) must be unique. An
    # endpoint-derived name is disambiguated instead, so two anonymous handlers
    # that slug to the same text can still coexist.
    explicit = !isnothing(config.toolname) || !Base.isgensym(signature.info.name)

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

    # Route-backed tools are invoked through the HTTP route's own request, not a
    # dedicated MCP stream, so they never take the Surface A injected handle.
    return store_tool!(ctx, wirename, description, func, signature, inject_request)
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
function store_tool!(ctx::ServerContext, wirename::String, description::String, func::Function, signature::HandlerSignature, inject_request::Bool)
    if haskey(ctx.mcp.tools, wirename)
        throw(ArgumentError("An MCP tool named `$wirename` is already registered"))
    end

    tool = MCPTool(wirename, description, func, signature.params, signature.argnames,
                   signature.has_context, signature.has_request, signature.has_stream,
                   inject_request, inputschema(signature.params))
    ctx.mcp.tools[wirename] = tool
    notify_tools_changed(ctx)
    return tool
end

# The client's per-request progress token (a string or integer per the spec).
function progress_token(params)::Any
    meta = get(params, META_KEY, nothing)
    if !(meta isa AbstractDict)
        return nothing
    end
    return get(meta, "progressToken", nothing)
end

# ----------------------------------------------------------------------------
# Methods
# ----------------------------------------------------------------------------

function tools_list(ctx::ServerContext; spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    tools = Dict{String,Any}[]
    for name in sort(collect(keys(ctx.mcp.tools)))
        tool = ctx.mcp.tools[name]
        push!(tools, Dict{String,Any}(
            "name" => tool.name,
            "description" => tool.description,
            "inputSchema" => inputschema(tool),
        ))
    end
    return list_result("tools", tools; spec=spec)
end

function call_tool(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params;
                   spec::Val=LATEST_LEGACY_SPEC)::Tuple{Union{Dict{String,Any},StreamedCall},Int}
    tool, arguments = resolve_registered_node(ctx.mcp.tools, id, params, "tool")
    if isnothing(tool)
        return arguments
    end

    token = progress_token(params)

    # Surface A: the handler declares an injected `; stream`, so the framework
    # owns the channel. Arguments are resolved before the producer starts, so a
    # validation failure stays a JSON-RPC error instead of becoming a streamed
    # isError result.
    if tool.has_stream
        stream = MCPStream(STREAM_BUFFER_SIZE; token=token, managed=true)
        pos_values, kwpairs = try
            resolve_registered(ctx, req, tool, arguments;
                               inject_request=tool.inject_request,
                               has_stream=true, stream=stream)
        catch error
            if !(error isa MCPRequestError)
                rethrow()
            end
            return request_error_body(id, error), 200
        end
        start_stream!(stream, _ -> tool.handler(pos_values...; kwpairs...))
        return StreamedCall(stream, id, spec), 200
    end

    try
        value = invoke_registered(ctx, req, tool, arguments; inject_request=tool.inject_request)
        # Surface B: a handler that called `mcp_stream` (or returned a raw
        # channel) hands the framework the event stream instead of a value.
        if value isa AbstractChannel
            return StreamedCall(adopt_stream(value, token), id, spec), 200
        end
        return result_response(ctx, id, tool_success_result(value; spec=spec); spec=spec)
    catch error
        if error isa MCPRequestError
            return request_error_body(id, error), 200
        end
        return result_response(ctx, id, toolerror_result(error); spec=spec)
    end
end

# ----------------------------------------------------------------------------
# Method routing
# ----------------------------------------------------------------------------

# Served in every revision; the result-shaping differences live behind the
# strategy interface (`list_result`, `tool_success_result`).
handle_method(spec::Val, ::Val{:tools_list}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session::Union{Nothing,MCPSession}=nothing) =
    result_response(ctx, id, tools_list(ctx; spec=spec); spec=spec)

handle_method(spec::Val, ::Val{:tools_call}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session::Union{Nothing,MCPSession}=nothing) =
    call_tool(ctx, req, id, params; spec=spec)
