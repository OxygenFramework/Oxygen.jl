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
    signature = reflect_handler(func)

    wirename = isnothing(name) ? string(signature.info.name) : string(name)

    if haskey(ctx.mcp.prompts, wirename)
        throw(ArgumentError("An MCP prompt named `$wirename` is already registered"))
    end

    prompt = MCPPrompt(wirename, string(desc), func, signature.params, signature.argnames,
                       signature.has_context, signature.has_request)
    ctx.mcp.prompts[wirename] = prompt
    notify_prompts_changed(ctx)
    return prompt
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
    return list_result("prompts", prompts; modern=modern)
end

function get_prompt(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params;
                    modern::Bool=false)::Tuple{Dict{String,Any},Int}
    prompt, arguments = resolve_registered_node(ctx.mcp.prompts, id, params, "prompt")
    isnothing(prompt) && return arguments

    try
        value = invoke_registered(ctx, req, prompt, arguments)
        result = Dict{String,Any}("messages" => prompt_result(value))
        isempty(prompt.description) || (result["description"] = prompt.description)
        return result_response(ctx, id, result; modern=modern)
    catch error
        error isa MCPRequestError && return request_error_body(id, error), 200
        return error_body(id, MCP_INTERNAL_ERROR, sprint(showerror, error)), 200
    end
end
