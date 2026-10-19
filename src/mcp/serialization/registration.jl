# Handler reflection shared by tool, prompt, and resource registration.
# Included into `MCP.Serialization` by `../serialization.jl`.
#
# These helpers build the reflected parameter view (`HandlerSignature`) that the
# domain registries store on their nodes. They live here so `MCP.Tools`,
# `MCP.Prompts`, and `MCP.Resources` can share them without depending on each
# other.

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
