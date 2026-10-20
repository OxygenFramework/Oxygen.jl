# Resource registration and metadata normalization.
# Included into `MCP.Resources` by `../resources.jl`.

# ----------------------------------------------------------------------------
# Registration (the only write path to the registries)
# ----------------------------------------------------------------------------

# A resource's handler parameters are either empty (static resource) or exactly
# the template variables (templated resource); anything else is an authoring
# error rather than a runtime surprise. `positional` carries every positional
# parameter name, including the injected names `reflect_handler` drops from
# the schema: a positional `request`/`context`/`stream` would be silently
# dropped and then fail at invocation time, because injection is keyword-based.
function validate_resource_params(
    uri::String,
    template::Bool,
    vars::Vector{String},
    mcp_params::Vector{MCPParam},
    positional::Vector{Symbol})

    for name in positional
        if name in (:context, :request, :stream)
            throw(ArgumentError(
                "MCP resource `$uri` declares a positional argument named `$name`; " *
                "injected `context`/`request` must be keyword arguments and resources " *
                "cannot take a `stream` handle"))
        end
    end

    supplied = Set(string(p.param.name) for p in mcp_params)

    if !template
        if !isempty(supplied)
            throw(ArgumentError(
                "MCP resource `$uri` is not a template, so its handler cannot declare " *
                "argument(s): $(join(string.(sort!(collect(supplied))), ", ")). Add `{...}` " *
                "placeholders to the URI or remove the parameters"))
        end
        return nothing
    end

    expected = Set(vars)
    unknown = sort!(collect(setdiff(supplied, expected)))
    missing_lookup = sort!(collect(setdiff(expected, supplied)))

    if !isempty(unknown)
        throw(ArgumentError(
            "Unknown MCP resource template variable(s) in handler: $(join(string.(unknown), ", ")). " *
            "The template declares: $(join(string.(sort!(collect(expected))), ", "))"))
    end
    if !isempty(missing_lookup)
        throw(ArgumentError(
            "Missing handler parameter(s) for MCP resource template `$uri`: $(join(string.(missing_lookup), ", "))"))
    end
    return nothing
end

# ----------------------------------------------------------------------------
# Resource metadata (annotations / icons)
# ----------------------------------------------------------------------------

const ANNOTATION_AUDIENCES = ("user", "assistant")
const ICON_THEMES = ("light", "dark")

# ISO 8601 calendar date with an optional time and offset:
# `YYYY-MM-DD`, `YYYY-MM-DDThh:mm`, `...:ss`, optional fractional seconds, and
# an optional `Z`/`±hh:mm` zone.
const ISO8601_TIMESTAMP = r"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?)?\z"

"""
    normalize_annotations(annotations) :: Union{Nothing,Dict}

Validate the optional spec `annotations` object: `audience` (an array of
`"user"`/`"assistant"`), `priority` (a number in `[0.0, 1.0]`), and
`lastModified` (an ISO 8601 string). Unknown keys are authoring errors rather
than silently dropped fields.
"""
function normalize_annotations(annotations) :: Nullable{Dict{String,Any}}
    if isnothing(annotations)
        return nothing
    end
    if !(annotations isa Union{NamedTuple,AbstractDict})
        throw(ArgumentError(
            "MCP resource annotations must be a NamedTuple or a Dict, got $(typeof(annotations))"))
    end

    normalized = string_keyed(annotations)
    for key in keys(normalized)
        if !(key in ("audience", "priority", "lastModified"))
            throw(ArgumentError(
                "Unknown MCP resource annotation `$key`; expected audience, priority, or lastModified"))
        end
    end

    if haskey(normalized, "audience")
        audience = normalized["audience"]
        if !(audience isa AbstractVector)
            throw(ArgumentError(
                "MCP resource annotation `audience` must be an array of roles"))
        end
        roles = String[]
        for role in audience
            if !(role isa AbstractString && String(role) in ANNOTATION_AUDIENCES)
                throw(ArgumentError(
                    "Invalid MCP resource annotation audience `$role`; expected \"user\" or \"assistant\""))
            end
            push!(roles, String(role))
        end
        normalized["audience"] = roles
    end

    if haskey(normalized, "priority")
        priority = normalized["priority"]
        if !(priority isa Real && !(priority isa Bool) && 0.0 <= priority <= 1.0)
            throw(ArgumentError(
                "MCP resource annotation `priority` must be a number between 0.0 and 1.0"))
        end
        normalized["priority"] = Float64(priority)
    end

    if haskey(normalized, "lastModified")
        last_modified = normalized["lastModified"]
        if !(last_modified isa AbstractString && occursin(ISO8601_TIMESTAMP, last_modified))
            throw(ArgumentError(
                "MCP resource annotation `lastModified` must be an ISO 8601 string"))
        end
        normalized["lastModified"] = String(last_modified)
    end

    return normalized
end

"""
    normalize_icons(icons) :: Union{Nothing,Vector{Dict}}

Validate the optional spec `icons` array. An icon is a `src` string shorthand
or a `NamedTuple`/`Dict` with a non-empty `src` plus optional `mimeType`,
`sizes` (an array of strings), and `theme` (`"light"`/`"dark"`).
"""
function normalize_icons(icons) :: Nullable{Vector{Dict{String,Any}}}
    if isnothing(icons)
        return nothing
    end
    entries = icons isa AbstractVector ? icons : [icons]
    if isempty(entries)
        throw(ArgumentError("MCP resource `icons` cannot be empty"))
    end
    return Dict{String,Any}[normalize_icon(icon) for icon in entries]
end

function normalize_icon(icon) :: Dict{String,Any}
    if icon isa AbstractString
        return Dict{String,Any}("src" => String(icon))
    end
    if !(icon isa Union{NamedTuple,AbstractDict})
        throw(ArgumentError(
            "MCP resource icons must be a `src` string or a NamedTuple/Dict, got $(typeof(icon))"))
    end

    normalized = string_keyed(icon)
    src = get(normalized, "src", nothing)
    if !(src isa AbstractString && !isempty(src))
        throw(ArgumentError(
            "MCP resource icon requires a non-empty `src` string"))
    end
    normalized["src"] = String(src)

    for key in keys(normalized)
        if !(key in ("src", "mimeType", "sizes", "theme"))
            throw(ArgumentError(
                "Unknown MCP resource icon field `$key`; expected src, mimeType, sizes, or theme"))
        end
    end

    if haskey(normalized, "mimeType")
        if !(normalized["mimeType"] isa AbstractString)
            throw(ArgumentError(
                "MCP resource icon `mimeType` must be a string"))
        end
        normalized["mimeType"] = String(normalized["mimeType"])
    end

    if haskey(normalized, "sizes")
        sizes = normalized["sizes"]
        if !(sizes isa AbstractVector && all(dimension -> dimension isa AbstractString, sizes))
            throw(ArgumentError(
                "MCP resource icon `sizes` must be an array of strings"))
        end
        normalized["sizes"] = String[String(dimension) for dimension in sizes]
    end

    if haskey(normalized, "theme")
        theme = normalized["theme"]
        if !(theme isa AbstractString && String(theme) in ICON_THEMES)
            throw(ArgumentError(
                "MCP resource icon `theme` must be \"light\" or \"dark\""))
        end
        normalized["theme"] = String(theme)
    end

    return normalized
end

"""
    register_resource!(ctx::ServerContext, uri, desc, func::Function;
                       name=nothing, title=nothing, mime_type=nothing, size=nothing,
                       annotations=nothing, icons=nothing)

Reflect on `func` and store the resulting `MCPResource` in `ctx.mcp.resources`
(static) or `ctx.mcp.resource_templates` (when `uri` carries `{var}`/`{+var}`
placeholders), keyed by the URI.

A static resource handler takes no arguments beyond the injected
`context`/`request`. A templated handler's parameters are the template
variables, so adding a `{var}` and a matching parameter keeps the two in sync.
The wire `name` defaults to the handler's name (falling back to the URI for
anonymous handlers) and `mime_type` becomes the default content type of
`resources/read` replies. `annotations` (`audience`/`priority`/`lastModified`)
and `icons` are validated and emitted on the resource entry.
"""
function register_resource!(
    ctx::ServerContext,
    uri::String,
    desc,
    func::Function;
    name=nothing,
    title=nothing,
    mime_type=nothing,
    size=nothing,
    annotations=nothing,
    icons=nothing)

    if isempty(uri)
        throw(ArgumentError("An MCP resource URI cannot be empty"))
    end
    if occursin(r"\s", uri)
        throw(ArgumentError("Invalid MCP resource URI `$uri`: whitespace is not allowed"))
    end

    # A stray `}` without `{` is malformed too; `template_variables` rejects it.
    template = occursin('{', uri) || occursin('}', uri)
    if template && !isnothing(size)
        throw(ArgumentError(
            "MCP resource template `$uri` cannot declare `size`: the field exists only " *
            "on static resources (templates describe no single byte length)"))
    end
    variables = template ? template_variables(uri) : TemplateVariable[]
    vars = [variable.name for variable in variables]
    pattern = template ? compile_template(uri, variables) : nothing
    normalized_annotations = normalize_annotations(annotations)
    normalized_icons = normalize_icons(icons)

    signature = reflect_handler(func)
    if signature.has_stream
        throw(ArgumentError("MCP resources cannot declare an injected `stream` handle"))
    end

    validate_resource_params(uri, template, vars, signature.params,
                             [p.name for p in signature.info.args])

    wirename = if isnothing(name)
        Base.isgensym(signature.info.name) ? uri : string(signature.info.name)
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
                           normalized_annotations, normalized_icons,
                           template, vars, pattern, func, signature.params, signature.argnames,
                           signature.has_context, signature.has_request)

    registry = template ? ctx.mcp.resource_templates : ctx.mcp.resources
    label = template ? "resource template" : "resource"
    if haskey(registry, uri)
        throw(ArgumentError("An MCP $label with URI `$uri` is already registered"))
    end
    registry[uri] = resource
    notify_change(ctx, :resources_changed)
    return resource
end
