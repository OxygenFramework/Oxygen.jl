# Prompt registration, prompt message serialization, and the `prompts/list` /
# `prompts/get` methods. Included into the `MCP` module by `../mcp.jl`.

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

"""
    register_prompt!(ctx::ServerContext, desc, func::Function; name=nothing)

Reflect on `func` and store the resulting `MCPPrompt` in `ctx.mcp.prompts` keyed
by its wire name. Unlike `register_tool!`, no parameter description map is taken:
the handler's own parameters *are* the prompt's template variables.
"""
function register_prompt!(ctx::ServerContext, desc, func::Function; name=nothing)
    info = Reflection.splitdef(func; start=1)

    method = first(methods(func))
    kwdecl = Base.kwarg_decl(method)
    has_context = :context in kwdecl
    has_request = :request in kwdecl

    argnames = Symbol[]
    mcp_params = MCPParam[]

    for p in info.args
        push!(argnames, p.name)
        push!(mcp_params, MCPParam(p, ""))
    end

    for p in info.kwargs
        # `context` / `request` are injected by the framework, never template variables
        p.name in (:context, :request) && continue
        push!(mcp_params, MCPParam(p, ""))
    end

    wirename = isnothing(name) ? string(info.name) : string(name)

    if haskey(ctx.mcp.prompts, wirename)
        throw(ArgumentError("An MCP prompt named `$wirename` is already registered"))
    end

    prompt = MCPPrompt(wirename, string(desc), func, mcp_params, argnames, has_context, has_request)
    ctx.mcp.prompts[wirename] = prompt
    return prompt
end

function invoke_prompt(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, prompt::MCPPrompt, arguments)
    return invoke_registered(ctx, req, prompt.handler, prompt.params, prompt.argnames,
                             prompt.has_context, prompt.has_request, arguments)
end

# ----------------------------------------------------------------------------
# Prompt result serialization
# ----------------------------------------------------------------------------

# The spec allows only `user` and `assistant` in prompt messages.
const PROMPT_ROLES = ("user", "assistant")

function normalize_role(role)::String
    r = lowercase(string(role))
    r in PROMPT_ROLES ||
        throw(ArgumentError("Invalid prompt role `$role`; expected \"user\" or \"assistant\""))
    return r
end

function prompt_message(role, content)::Dict{String,Any}
    return Dict{String,Any}(
        "role" => normalize_role(role),
        "content" => content_block(content),
    )
end

# Normalize a prompt handler's return value into a `messages` array. Supported
# forms: a `String`/`HTTP.Response`/raw bytes (one user message), a `Pair`
# role => content, or a vector mixing `Pair`s, `String`s and pre-shaped message
# dicts.
function prompt_result(value)
    if value isa Pair
        return Any[prompt_message(value.first, value.second)]
    elseif value isa AbstractString || value isa HTTP.Response || value isa AbstractVector{UInt8}
        return Any[prompt_message("user", value)]
    elseif value isa AbstractVector
        return Any[_prompt_entry(item) for item in value]
    else
        return Any[prompt_message("user", value)]
    end
end

function _prompt_entry(item)
    if item isa Pair
        return prompt_message(item.first, item.second)
    elseif item isa AbstractDict && haskey(item, "role") && haskey(item, "content")
        return prompt_message(item["role"], item["content"])
    else
        return prompt_message("user", item)
    end
end

# ----------------------------------------------------------------------------
# Methods
# ----------------------------------------------------------------------------

# The prompt's argument list is its handler signature: every non-injected
# parameter becomes a template variable, required when it has no default.
function prompt_arguments(prompt::MCPPrompt)::Vector{Any}
    args = Any[]
    for p in prompt.params
        push!(args, Dict{String,Any}(
            "name" => String(p.param.name),
            "required" => isrequired(p.param),
        ))
    end
    return args
end

function prompts_list(ctx::ServerContext; modern::Bool=true)::Dict{String,Any}
    prompts = Dict{String,Any}[]
    for name in sort(collect(keys(ctx.mcp.prompts)))
        prompt = ctx.mcp.prompts[name]
        push!(prompts, Dict{String,Any}(
            "name" => prompt.name,
            "description" => prompt.description,
            "arguments" => prompt_arguments(prompt),
        ))
    end
    result = Dict{String,Any}("prompts" => prompts)
    if modern
        result["ttlMs"] = LIST_TTL_MS
        result["cacheScope"] = "public"
    end
    return result
end

function get_prompt(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params;
                    modern::Bool=false)::Tuple{Dict{String,Any},Int}
    body_name = get(params, "name", nothing)
    if isnothing(body_name)
        return error_body(id, MCP_INVALID_PARAMS, "Missing prompt name"), 200
    end

    wirename = String(body_name)
    prompt = get(ctx.mcp.prompts, wirename, nothing)
    if isnothing(prompt)
        return error_body(id, MCP_INVALID_PARAMS, "Unknown prompt: $wirename"), 200
    end

    arguments = get(params, "arguments", Dict{String,Any}())
    isnothing(arguments) && (arguments = Dict{String,Any}())
    if !(arguments isa AbstractDict)
        return error_body(id, MCP_INVALID_PARAMS, "Invalid arguments: expected an object"), 200
    end

    try
        value = invoke_prompt(ctx, req, prompt, arguments)
        result = Dict{String,Any}("messages" => prompt_result(value))
        isempty(prompt.description) || (result["description"] = prompt.description)
        modern && (result = modern_envelope(ctx, result))
        return result_body(id, result), 200
    catch error
        if error isa MCPRequestError
            return error_body(id, error.code, error.message, error.data), 200
        end
        return error_body(id, MCP_INTERNAL_ERROR, sprint(showerror, error)), 200
    end
end
