# Resource registration, URI-template matching, content serialization, and the
# `resources/list` / `resources/templates/list` / `resources/read` methods.
# Included into the `MCP` module by `../mcp.jl`.

# ----------------------------------------------------------------------------
# URI templates (RFC 6570 level 1: simple `{var}` string expansion)
# ----------------------------------------------------------------------------

# Template expressions are matched whole so nested/operator forms (`{+var}`,
# `{?var}`, `{var*}`) fall through to the validation errors below.
const TEMPLATE_EXPRESSION = r"\{([^{}]*)\}"

# Template variables double as handler argument names, so they must be valid
# Julia identifiers.
const TEMPLATE_VARIABLE = r"^[A-Za-z_][A-Za-z0-9_]*$"

"""
    template_vars(uri) :: Vector{String}

Extract the `{var}` names from an MCP resource URI template, in order. Only
RFC 6570 level-1 simple expressions with identifier-safe names are supported;
anything else (operators, empty names, unbalanced braces) is rejected with an
`ArgumentError`.
"""
function template_vars(uri::String)::Vector{String}
    vars = String[]
    for matched in eachmatch(TEMPLATE_EXPRESSION, uri)
        name = String(matched.captures[1])
        occursin(TEMPLATE_VARIABLE, name) || throw(ArgumentError(
            "Invalid MCP resource template expression `{$name}`: only simple `{name}` " *
            "expansions with identifier-safe names are supported"))
        name in vars && throw(ArgumentError(
            "Duplicate MCP resource template variable `{$name}`"))
        push!(vars, name)
    end

    # Whatever text the expressions leave behind decides whether the braces were
    # balanced: `{a{b}}` still carries a `{` once `{b}` is removed.
    remainder = replace(uri, TEMPLATE_EXPRESSION => "")
    (occursin('{', remainder) || occursin('}', remainder)) && throw(ArgumentError(
        "Malformed MCP resource template URI `$uri`: unbalanced braces"))

    return vars
end

function escape_regex(literal::AbstractString)::String
    return replace(literal, r"([\\^$.|?*+()\[\]{}])" => s"\\\1")
end

# Compile a template into an anchored regex whose positional capture groups
# correspond, in order, to `vars`. Literal segments are matched verbatim and
# variables capture a single path segment, since RFC 6570 simple expansion
# percent-encodes `/` inside the value.
function compile_template(uri::String, vars::Vector{String})::Regex
    buffer = IOBuffer()
    write(buffer, "^")
    position = 1
    for matched in eachmatch(TEMPLATE_EXPRESSION, uri)
        write(buffer, escape_regex(uri[position:(matched.offset - 1)]))
        write(buffer, "([^/]+)")
        position = matched.offset + ncodeunits(matched.match)
    end
    write(buffer, escape_regex(uri[position:end]))
    write(buffer, "\$")
    return Regex(String(take!(buffer)))
end

"""
    match_template(resource, uri) :: Union{Nothing,Dict{String,Any}}

Match a requested URI against a registered template, returning the decoded
template variables as a client-argument dictionary, or `nothing` when the URI
does not fit the template.
"""
function match_template(resource::MCPResource, uri::String)::Union{Nothing,Dict{String,Any}}
    pattern = resource.pattern
    isnothing(pattern) && return nothing

    matched = match(pattern, uri)
    isnothing(matched) && return nothing

    arguments = Dict{String,Any}()
    for (index, variable) in enumerate(resource.vars)
        arguments[variable] = HTTP.unescapeuri(matched.captures[index])
    end
    return arguments
end

# ----------------------------------------------------------------------------
# Registration (the only write path to the registries)
# ----------------------------------------------------------------------------

# A resource's handler parameters are either empty (static resource) or exactly
# the template variables (templated resource); anything else is an authoring
# error rather than a runtime surprise. `positional` carries every positional
# parameter name, including the injected names `reflect_mcp_params` drops from
# the schema: a positional `request`/`context`/`stream` would be silently
# dropped and then fail at invocation time, because injection is keyword-based.
function validate_resource_params(uri::String, template::Bool, vars::Vector{String},
                                  mcp_params::Vector{MCPParam}, positional::Vector{Symbol})
    for name in positional
        name in (:context, :request, :stream) && throw(ArgumentError(
            "MCP resource `$uri` declares a positional argument named `$name`; " *
            "injected `context`/`request` must be keyword arguments and resources " *
            "cannot take a `stream` handle"))
    end

    supplied = Set(string(p.param.name) for p in mcp_params)

    if !template
        isempty(supplied) || throw(ArgumentError(
            "MCP resource `$uri` is not a template, so its handler cannot declare " *
            "argument(s): $(join(string.(sort!(collect(supplied))), ", ")). Add `{...}` " *
            "placeholders to the URI or remove the parameters"))
        return nothing
    end

    expected = Set(vars)
    unknown = sort!(collect(setdiff(supplied, expected)))
    missing = sort!(collect(setdiff(expected, supplied)))

    isempty(unknown) || throw(ArgumentError(
        "Unknown MCP resource template variable(s) in handler: $(join(string.(unknown), ", ")). " *
        "The template declares: $(join(string.(sort!(collect(expected))), ", "))"))
    isempty(missing) || throw(ArgumentError(
        "Missing handler parameter(s) for MCP resource template `$uri`: $(join(string.(missing), ", "))"))
    return nothing
end

"""
    register_resource!(ctx::ServerContext, uri, desc, func::Function;
                       name=nothing, title=nothing, mime_type=nothing, size=nothing)

Reflect on `func` and store the resulting `MCPResource` in `ctx.mcp.resources`
(static) or `ctx.mcp.resource_templates` (when `uri` carries `{var}`
placeholders), keyed by the URI.

A static resource handler takes no arguments beyond the injected
`context`/`request`. A templated handler's parameters are the template
variables, so adding a `{var}` and a matching parameter keeps the two in sync.
The wire `name` defaults to the handler's name (falling back to the URI for
anonymous handlers) and `mime_type` becomes the default content type of
`resources/read` replies.
"""
function register_resource!(ctx::ServerContext, uri::String, desc, func::Function;
                            name=nothing, title=nothing, mime_type=nothing, size=nothing)
    isempty(uri) && throw(ArgumentError("An MCP resource URI cannot be empty"))
    occursin(r"\s", uri) && throw(ArgumentError("Invalid MCP resource URI `$uri`: whitespace is not allowed"))

    # A stray `}` without `{` is malformed too; `template_vars` rejects it.
    template = occursin('{', uri) || occursin('}', uri)
    template && !isnothing(size) && throw(ArgumentError(
        "MCP resource template `$uri` cannot declare `size`: the field exists only " *
        "on static resources (templates describe no single byte length)"))
    vars = template ? template_vars(uri) : String[]
    pattern = template ? compile_template(uri, vars) : nothing

    info, argnames, mcp_params = reflect_mcp_params(func, Dict{Symbol,String}(), Dict{Symbol,String}())
    has_context, has_request, has_stream = injected_kwargs(func)
    has_stream && throw(ArgumentError("MCP resources cannot declare an injected `stream` handle"))

    validate_resource_params(uri, template, vars, mcp_params, [p.name for p in info.args])

    wirename = if isnothing(name)
        Base.isgensym(info.name) ? uri : string(info.name)
    else
        string(name)
    end

    own = string(desc)
    description = isempty(own) ? function_docstring(func) : own

    resource = MCPResource(uri, wirename,
                           isnothing(title) ? nothing : string(title),
                           description,
                           isnothing(mime_type) ? nothing : string(mime_type),
                           isnothing(size) ? nothing : Int(size),
                           template, vars, pattern, func, mcp_params, argnames,
                           has_context, has_request)

    if template
        haskey(ctx.mcp.resource_templates, uri) && throw(ArgumentError(
            "An MCP resource template with URI `$uri` is already registered"))
        ctx.mcp.resource_templates[uri] = resource
    else
        haskey(ctx.mcp.resources, uri) && throw(ArgumentError(
            "An MCP resource with URI `$uri` is already registered"))
        ctx.mcp.resources[uri] = resource
    end
    notify_resources_changed(ctx)
    return resource
end

function invoke_resource(ctx::ServerContext, req::Union{Nothing,HTTP.Request},
                         resource::MCPResource, arguments)
    return invoke_registered(ctx, req, resource.handler, resource.params, resource.argnames,
                             resource.has_context, resource.has_request, arguments)
end

# ----------------------------------------------------------------------------
# Resource content serialization
# ----------------------------------------------------------------------------

# `resources/read` contents carry `uri`/`mimeType` plus exactly one of `text` or
# `blob` — the content-block shape (`type`/`resource`) is for tool results.
resource_text(uri::String, mime::AbstractString, content)::Dict{String,Any} =
    Dict{String,Any}("uri" => uri, "mimeType" => String(mime), "text" => string(content))

resource_blob(uri::String, mime::AbstractString, bytes::AbstractVector{UInt8})::Dict{String,Any} =
    Dict{String,Any}("uri" => uri, "mimeType" => String(mime), "blob" => base64encode(bytes))

function resource_bytes(uri::String, mime::AbstractString, bytes::AbstractVector{UInt8})::Dict{String,Any}
    return is_text_mime(mime) ? resource_text(uri, mime, String(bytes)) : resource_blob(uri, mime, bytes)
end

"""
    resource_content(resource, uri, value) :: Dict

Serialize one resource content entry. `HTTP.Response` values honor their
`Content-Type`; `String`s become `text`; raw bytes become `text` for textual
media and base64 `blob` otherwise; a dict already carrying `text`/`blob` passes
through; a `Pair` overrides the entry's URI; anything else is JSON-encoded into
`text`. The resource's declared `mime_type` is the fallback when the value does
not supply one.
"""
function resource_content(resource::MCPResource, uri::String, value)::Dict{String,Any}
    declared = resource.mime_type

    if value isa HTTP.Response
        return resource_bytes(uri, response_mime(value), response_bytes(value))
    elseif value isa AbstractString
        return resource_text(uri, something(declared, "text/plain"), value)
    elseif value isa AbstractVector{UInt8}
        return resource_bytes(uri, something(declared, HTTP.sniff(value)), value)
    elseif value isa Pair
        return resource_content(resource, string(value.first), value.second)
    elseif value isa AbstractDict && (haskey(value, "text") || haskey(value, "blob"))
        return value
    else
        return resource_text(uri, something(declared, "application/json"), JSON.json(value))
    end
end

# Normalize a handler return value into a `resources/read` result. A vector of
# values becomes multiple contents, `Pair`s may restate the URI per entry, and a
# dict already shaped as a result (`"contents"`) passes through untouched.
function resource_result(resource::MCPResource, uri::String, value)::Dict{String,Any}
    if value isa AbstractDict && haskey(value, "contents")
        return value
    elseif value isa AbstractVector && !(value isa AbstractVector{UInt8})
        return Dict{String,Any}("contents" => Any[resource_content(resource, uri, item) for item in value])
    else
        return Dict{String,Any}("contents" => Any[resource_content(resource, uri, value)])
    end
end

# ----------------------------------------------------------------------------
# Methods
# ----------------------------------------------------------------------------

# Static entries and template entries share the same wire fields except for the
# identifier key (`uri` vs `uriTemplate`).
function resource_entry(resource::MCPResource)::Dict{String,Any}
    entry = Dict{String,Any}(
        "name" => resource.name,
        "description" => resource.description,
    )
    entry[resource.template ? "uriTemplate" : "uri"] = resource.uri
    isnothing(resource.title) || (entry["title"] = resource.title)
    isnothing(resource.mime_type) || (entry["mimeType"] = resource.mime_type)
    isnothing(resource.size) || (entry["size"] = resource.size)
    return entry
end

function resources_list(ctx::ServerContext; modern::Bool=true)::Dict{String,Any}
    resources = Dict{String,Any}[]
    for uri in sort(collect(keys(ctx.mcp.resources)))
        push!(resources, resource_entry(ctx.mcp.resources[uri]))
    end
    result = Dict{String,Any}("resources" => resources)
    if modern
        result["ttlMs"] = LIST_TTL_MS
        result["cacheScope"] = "public"
    end
    return result
end

function resource_templates_list(ctx::ServerContext; modern::Bool=true)::Dict{String,Any}
    templates = Dict{String,Any}[]
    for uri in sort(collect(keys(ctx.mcp.resource_templates)))
        push!(templates, resource_entry(ctx.mcp.resource_templates[uri]))
    end
    result = Dict{String,Any}("resourceTemplates" => templates)
    if modern
        result["ttlMs"] = LIST_TTL_MS
        result["cacheScope"] = "public"
    end
    return result
end

# Resolve a requested URI to its resource. Exact registrations win over
# templates; templates are scanned in sorted order so overlapping templates
# resolve deterministically.
function resolve_resource(ctx::ServerContext, uri::String)
    resource = get(ctx.mcp.resources, uri, nothing)
    !isnothing(resource) && return resource, Dict{String,Any}()

    for template in sort(collect(keys(ctx.mcp.resource_templates)))
        candidate = ctx.mcp.resource_templates[template]
        arguments = match_template(candidate, uri)
        isnothing(arguments) || return candidate, arguments
    end
    return nothing
end

function read_resource(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params;
                       modern::Bool=false)::Tuple{Dict{String,Any},Int}
    body_uri = get(params, "uri", nothing)
    if !(body_uri isa AbstractString) || isempty(body_uri)
        return error_body(id, MCP_INVALID_PARAMS, "Missing resource URI"), 200
    end

    uri = String(body_uri)
    resolved = resolve_resource(ctx, uri)
    if isnothing(resolved)
        # The modern revision folded not-found into -32602; the legacy
        # revisions defined the dedicated -32002.
        code = modern ? MCP_INVALID_PARAMS : MCP_RESOURCE_NOT_FOUND
        return error_body(id, code, "Resource not found", Dict{String,Any}("uri" => uri)), 200
    end

    resource, arguments = resolved
    try
        value = invoke_resource(ctx, req, resource, arguments)
        result = resource_result(resource, uri, value)
        if modern
            result["ttlMs"] = LIST_TTL_MS
            result["cacheScope"] = "private"
            result = modern_envelope(ctx, result)
        end
        return result_body(id, result), 200
    catch error
        if error isa MCPRequestError
            return error_body(id, error.code, error.message, error.data), 200
        end
        return error_body(id, MCP_INTERNAL_ERROR, sprint(showerror, error)), 200
    end
end
