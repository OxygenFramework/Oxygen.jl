# Resource registration, URI-template matching, content serialization, and the
# `resources/list` / `resources/templates/list` / `resources/read` methods.
# Included into the `MCP` module by `../mcp.jl`.

# ----------------------------------------------------------------------------
# URI templates (RFC 6570: simple `{var}` and reserved `{+var}` expansion)
# ----------------------------------------------------------------------------

# Template expressions are matched whole so nested/operator forms (`{?var}`,
# `{#var}`, `{var*}`) fall through to the validation errors below. The `+` of a
# reserved expansion is the only operator accepted.
const TEMPLATE_EXPRESSION = r"\{([^{}]*)\}"

# Template variables double as handler argument names, so they must be valid
# Julia identifiers. The optional leading `+` selects reserved expansion.
const TEMPLATE_VARIABLE = r"^(\+?)([A-Za-z_][A-Za-z0-9_]*)\z"

# One validated template expression: `name` is the bare variable name and
# `reserved` records whether the `+` operator was used.
struct TemplateVariable
    name     :: String
    reserved :: Bool
end

"""
    template_variables(uri) :: Vector{TemplateVariable}

Parse an MCP resource URI template, in order. Simple `{var}` expansions capture
a single path segment (RFC 6570 percent-encodes `/` inside the value); reserved
`{+var}` expansions capture across `/`, so nested paths can be served. Anything
else (other operators, empty names, unbalanced braces) is rejected with an
`ArgumentError`.
"""
function template_variables(uri::String)::Vector{TemplateVariable}
    variables = TemplateVariable[]
    for matched in eachmatch(TEMPLATE_EXPRESSION, uri)
        expression = String(matched.captures[1])
        parsed = match(TEMPLATE_VARIABLE, expression)
        isnothing(parsed) && throw(ArgumentError(
            "Invalid MCP resource template expression `{$expression}`: only simple " *
            "`{name}` and reserved `{+name}` expansions with identifier-safe names are supported"))
        name = String(parsed.captures[2])
        reserved = !isempty(parsed.captures[1])
        any(variable -> variable.name == name, variables) && throw(ArgumentError(
            "Duplicate MCP resource template variable `{$name}`"))
        push!(variables, TemplateVariable(name, reserved))
    end

    # Whatever text the expressions leave behind decides whether the braces were
    # balanced: `{a{b}}` still carries a `{` once `{b}` is removed.
    remainder = replace(uri, TEMPLATE_EXPRESSION => "")
    (occursin('{', remainder) || occursin('}', remainder)) && throw(ArgumentError(
        "Malformed MCP resource template URI `$uri`: unbalanced braces"))

    return variables
end

"""
    template_vars(uri) :: Vector{String}

The variable names of a resource URI template, in order. See `template_variables`
for the full parse.
"""
template_vars(uri::String)::Vector{String} = [variable.name for variable in template_variables(uri)]

function escape_regex(literal::AbstractString)::String
    return replace(literal, r"([\\^$.|?*+()\[\]{}])" => s"\\\1")
end

# Compile a template into an anchored regex whose positional capture groups
# correspond, in order, to `variables`. Literal segments are matched verbatim; a
# simple variable captures a single path segment (RFC 6570 encodes `/` inside the
# value), while a reserved variable captures any run — `.+` so an empty path
# cannot match. Greedy reserved captures resolve multiple-variable templates
# against the last possible separator, which is deterministic.
function compile_template(uri::String, variables::Vector{TemplateVariable})::Regex
    buffer = IOBuffer()
    write(buffer, "^")
    position = 1
    for (matched, variable) in zip(eachmatch(TEMPLATE_EXPRESSION, uri), variables)
        write(buffer, escape_regex(uri[position:(matched.offset - 1)]))
        write(buffer, variable.reserved ? "(.+)" : "([^/]+)")
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
        capture = try
            HTTP.unescapeuri(matched.captures[index])
        catch
            # A malformed percent-escape (`%`, `%2`, `%zz`, ...) cannot name
            # this resource; leave it unmatched so the read ends as the era's
            # not-found error instead of crashing the request.
            return nothing
        end
        arguments[variable] = capture
    end
    return arguments
end

# ----------------------------------------------------------------------------
# Registration (the only write path to the registries)
# ----------------------------------------------------------------------------

# A resource's handler parameters are either empty (static resource) or exactly
# the template variables (templated resource); anything else is an authoring
# error rather than a runtime surprise. `positional` carries every positional
# parameter name, including the injected names `reflect_handler` drops from
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
function normalize_annotations(annotations)::Nullable{Dict{String,Any}}
    isnothing(annotations) && return nothing
    annotations isa Union{NamedTuple,AbstractDict} || throw(ArgumentError(
        "MCP resource annotations must be a NamedTuple or a Dict, got $(typeof(annotations))"))

    normalized = string_keyed(annotations)
    for key in keys(normalized)
        key in ("audience", "priority", "lastModified") || throw(ArgumentError(
            "Unknown MCP resource annotation `$key`; expected audience, priority, or lastModified"))
    end

    if haskey(normalized, "audience")
        audience = normalized["audience"]
        audience isa AbstractVector || throw(ArgumentError(
            "MCP resource annotation `audience` must be an array of roles"))
        roles = String[]
        for role in audience
            (role isa AbstractString && String(role) in ANNOTATION_AUDIENCES) || throw(ArgumentError(
                "Invalid MCP resource annotation audience `$role`; expected \"user\" or \"assistant\""))
            push!(roles, String(role))
        end
        normalized["audience"] = roles
    end

    if haskey(normalized, "priority")
        priority = normalized["priority"]
        (priority isa Real && !(priority isa Bool) && 0.0 <= priority <= 1.0) || throw(ArgumentError(
            "MCP resource annotation `priority` must be a number between 0.0 and 1.0"))
        normalized["priority"] = Float64(priority)
    end

    if haskey(normalized, "lastModified")
        last_modified = normalized["lastModified"]
        (last_modified isa AbstractString && occursin(ISO8601_TIMESTAMP, last_modified)) || throw(ArgumentError(
            "MCP resource annotation `lastModified` must be an ISO 8601 string"))
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
function normalize_icons(icons)::Nullable{Vector{Dict{String,Any}}}
    isnothing(icons) && return nothing
    entries = icons isa AbstractVector ? icons : [icons]
    isempty(entries) && throw(ArgumentError("MCP resource `icons` cannot be empty"))
    return Dict{String,Any}[normalize_icon(icon) for icon in entries]
end

function normalize_icon(icon)::Dict{String,Any}
    icon isa AbstractString && return Dict{String,Any}("src" => String(icon))
    icon isa Union{NamedTuple,AbstractDict} || throw(ArgumentError(
        "MCP resource icons must be a `src` string or a NamedTuple/Dict, got $(typeof(icon))"))

    normalized = string_keyed(icon)
    src = get(normalized, "src", nothing)
    (src isa AbstractString && !isempty(src)) || throw(ArgumentError(
        "MCP resource icon requires a non-empty `src` string"))
    normalized["src"] = String(src)

    for key in keys(normalized)
        key in ("src", "mimeType", "sizes", "theme") || throw(ArgumentError(
            "Unknown MCP resource icon field `$key`; expected src, mimeType, sizes, or theme"))
    end

    if haskey(normalized, "mimeType")
        normalized["mimeType"] isa AbstractString || throw(ArgumentError(
            "MCP resource icon `mimeType` must be a string"))
        normalized["mimeType"] = String(normalized["mimeType"])
    end

    if haskey(normalized, "sizes")
        sizes = normalized["sizes"]
        (sizes isa AbstractVector && all(size -> size isa AbstractString, sizes)) || throw(ArgumentError(
            "MCP resource icon `sizes` must be an array of strings"))
        normalized["sizes"] = String[String(size) for size in sizes]
    end

    if haskey(normalized, "theme")
        theme = normalized["theme"]
        (theme isa AbstractString && String(theme) in ICON_THEMES) || throw(ArgumentError(
            "MCP resource icon `theme` must be \"light\" or \"dark\""))
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
function register_resource!(ctx::ServerContext, uri::String, desc, func::Function;
                            name=nothing, title=nothing, mime_type=nothing, size=nothing,
                            annotations=nothing, icons=nothing)
    isempty(uri) && throw(ArgumentError("An MCP resource URI cannot be empty"))
    occursin(r"\s", uri) && throw(ArgumentError("Invalid MCP resource URI `$uri`: whitespace is not allowed"))

    # A stray `}` without `{` is malformed too; `template_variables` rejects it.
    template = occursin('{', uri) || occursin('}', uri)
    template && !isnothing(size) && throw(ArgumentError(
        "MCP resource template `$uri` cannot declare `size`: the field exists only " *
        "on static resources (templates describe no single byte length)"))
    variables = template ? template_variables(uri) : TemplateVariable[]
    vars = [variable.name for variable in variables]
    pattern = template ? compile_template(uri, variables) : nothing
    normalized_annotations = normalize_annotations(annotations)
    normalized_icons = normalize_icons(icons)

    signature = reflect_handler(func)
    signature.has_stream && throw(ArgumentError("MCP resources cannot declare an injected `stream` handle"))

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

# Normalize a pre-shaped content dict into a schema-valid ResourceContents: the
# `uri` is filled when missing, the declared MIME type becomes the default, and
# exactly one of `text`/`blob` must be present. Unknown keys (`annotations`,
# `_meta`, ...) pass through untouched. A malformed entry is an authoring bug,
# so it surfaces as -32603 rather than a client params error.
function normalize_content_entry(uri::String, declared_mime::Nullable{String},
                                 entry::AbstractDict)::Dict{String,Any}
    content = string_keyed(entry)

    has_text = haskey(content, "text")
    has_blob = haskey(content, "blob")
    if has_text == has_blob
        detail = has_text ? "`text` and `blob` are mutually exclusive" :
                            "exactly one of `text` or `blob` is required"
        throw(MCPRequestError(MCP_INTERNAL_ERROR, "Invalid resource content: $detail"))
    end

    if !haskey(content, "uri")
        content["uri"] = uri
    else
        content["uri"] isa AbstractString || throw(MCPRequestError(
            MCP_INTERNAL_ERROR, "Invalid resource content: `uri` must be a string"))
    end
    if has_text
        content["text"] isa AbstractString || throw(MCPRequestError(
            MCP_INTERNAL_ERROR, "Invalid resource content: `text` must be a string"))
    else
        content["blob"] isa AbstractString || throw(MCPRequestError(
            MCP_INTERNAL_ERROR, "Invalid resource content: `blob` must be a base64 string"))
    end
    if !haskey(content, "mimeType") && !isnothing(declared_mime)
        content["mimeType"] = declared_mime
    end

    return content
end

"""
    resource_content(resource, uri, value) :: Dict

Serialize one resource content entry. `HTTP.Response` values honor their
`Content-Type`; `String`s become `text`; raw bytes become `text` for textual
media and base64 `blob` otherwise; a dict already carrying `text`/`blob` is
normalized (missing `uri`/`mimeType` filled, extra fields preserved); a `Pair`
overrides the entry's URI; anything else is JSON-encoded into `text`. The
resource's declared `mime_type` is the fallback when the value does not supply
one.
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
        return normalize_content_entry(uri, declared, value)
    else
        return resource_text(uri, something(declared, "application/json"), JSON.json(value))
    end
end

# A dict entry inside a pre-shaped `contents` array is an authoring-provided
# ResourceContents, so it must already carry exactly one of `text`/`blob`;
# a missing or doubled pair is a server bug (-32603). Non-dict values keep the
# usual serialization (a `Pair` may still restate the entry URI).
function contents_entry(resource::MCPResource, uri::String, value)::Dict{String,Any}
    return value isa AbstractDict ? normalize_content_entry(uri, resource.mime_type, value) :
                                    resource_content(resource, uri, value)
end

# Normalize a handler return value into a `resources/read` result. A vector of
# values becomes multiple contents, `Pair`s may restate the URI per entry, and a
# dict already shaped as a result (`"contents"`) has every entry normalized so
# the reply is always schema-valid.
function resource_result(resource::MCPResource, uri::String, value)::Dict{String,Any}
    if value isa AbstractDict && haskey(value, "contents")
        raw = value["contents"]
        (raw isa AbstractVector && !(raw isa AbstractVector{UInt8})) || throw(MCPRequestError(
            MCP_INTERNAL_ERROR, "Invalid resource result: `contents` must be an array"))
        result = string_keyed(value)
        result["contents"] = Any[contents_entry(resource, uri, item) for item in raw]
        return result
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
# identifier key (`uri` vs `uriTemplate`). `icons` postdates the oldest legacy
# revisions, so `version` (when known) gates it off for clients that may reject
# unknown fields; passing `nothing` keeps it for direct callers.
function resource_entry(resource::MCPResource;
                        version::Union{Nothing,AbstractString}=nothing)::Dict{String,Any}
    entry = Dict{String,Any}(
        "name" => resource.name,
        "description" => resource.description,
    )
    entry[resource.template ? "uriTemplate" : "uri"] = resource.uri
    isnothing(resource.title) || (entry["title"] = resource.title)
    isnothing(resource.mime_type) || (entry["mimeType"] = resource.mime_type)
    isnothing(resource.size) || (entry["size"] = resource.size)
    isnothing(resource.annotations) || (entry["annotations"] = resource.annotations)
    if isnothing(version) || supports_resource_icons(version)
        isnothing(resource.icons) || (entry["icons"] = resource.icons)
    end
    return entry
end

function resource_list(entries::Dict{String,MCPResource}, key::String;
                       modern::Bool=true, version::Union{Nothing,AbstractString}=nothing)::Dict{String,Any}
    items = [resource_entry(entries[uri]; version=version) for uri in sort(collect(keys(entries)))]
    return list_result(key, items; modern=modern)
end

function resources_list(ctx::ServerContext; modern::Bool=true,
                        version::Union{Nothing,AbstractString}=nothing)::Dict{String,Any}
    return resource_list(ctx.mcp.resources, "resources"; modern=modern, version=version)
end

function resource_templates_list(ctx::ServerContext; modern::Bool=true,
                                 version::Union{Nothing,AbstractString}=nothing)::Dict{String,Any}
    return resource_list(ctx.mcp.resource_templates, "resourceTemplates"; modern=modern, version=version)
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
        value = invoke_registered(ctx, req, resource, arguments)
        result = resource_result(resource, uri, value)
        if modern
            result["ttlMs"] = LIST_TTL_MS
            result["cacheScope"] = "private"
        end
        return result_response(ctx, id, result; modern=modern)
    catch error
        if error isa MCPRequestError
            # A handler that cannot resolve its URI (e.g. the folder helper)
            # throws the legacy not-found code; translate it by era like the
            # unresolved-URI path above.
            code = (modern && error.code == MCP_RESOURCE_NOT_FOUND) ?
                MCP_INVALID_PARAMS : error.code
            return request_error_body(id, error, code), 200
        end
        return error_body(id, MCP_INTERNAL_ERROR, sprint(showerror, error)), 200
    end
end

# ----------------------------------------------------------------------------
# Folder-backed resources
# ----------------------------------------------------------------------------

# Extension => MIME type for the folder helper. `HTTP.sniff` covers the rest.
const FOLDER_MIME_TYPES = Dict{String,String}(
    "txt" => "text/plain", 
    "md" => "text/markdown", "markdown" => "text/markdown",
    "html" => "text/html", "htm" => "text/html",
    "css" => "text/css",
    "js" => "text/javascript", "mjs" => "text/javascript", 
    "json" => "application/json",
    "xml" => "application/xml", 
    "csv" => "text/csv", 
    "log" => "text/plain", "jl" => "text/plain", 
    "toml" => "application/toml",
    "yaml" => "application/yaml", "yml" => "application/yaml",
    "svg" => "image/svg+xml", "png" => "image/png", "jpg" => "image/jpeg", "jpeg" => "image/jpeg", "gif" => "image/gif", "webp" => "image/webp",
    "pdf" => "application/pdf", "zip" => "application/zip",
)

# True when `candidate` is `root` itself or sits below it.
function is_within(root::String, candidate::String)::Bool
    separator = Sys.iswindows() ? "\\" : "/"
    prefix = endswith(root, separator) ? root : root * separator
    return candidate == root || startswith(candidate, prefix)
end

folder_not_found(uri::String) = throw(MCPRequestError(
    MCP_RESOURCE_NOT_FOUND, "Resource not found", Dict{String,Any}("uri" => uri)))

function folder_mime(path::AbstractString, bytes::Vector{UInt8}, mime_types)::String
    extension = lowercase(splitext(path)[2])
    key = startswith(extension, ".") ? extension[2:end] : extension
    if !isnothing(mime_types)
        haskey(mime_types, extension) && return String(mime_types[extension])
        haskey(mime_types, key) && return String(mime_types[key])
        # Caller-supplied keys are matched case-insensitively too, with or
        # without the leading dot.
        for (candidate, mime) in mime_types
            candidate isa AbstractString || continue
            normalized = lowercase(String(candidate))
            (normalized == extension || normalized == key) && return String(mime)
        end
    end
    haskey(FOLDER_MIME_TYPES, key) && return FOLDER_MIME_TYPES[key]
    return HTTP.sniff(bytes)
end

# Read a regular file through an `O_NOFOLLOW` handle on POSIX so a symlink
# swapped in after the `realpath` check cannot redirect the read (the parent
# directories are already canonical at that point). Windows has no equivalent
# here and falls back to a plain read. Errors (deleted file, ELOOP, ...) are
# the caller's to map.
function read_folder_file(path::String)::Vector{UInt8}
    if Sys.isunix()
        handle = Base.Filesystem.open(path,
            Base.Filesystem.JL_O_RDONLY | Base.Filesystem.JL_O_NOFOLLOW)
        try
            io = Base.fdio(reinterpret(Int32, Base.Filesystem.fd(handle)))
            return read(io)
        finally
            Base.Filesystem.close(handle)
        end
    end
    return read(path)
end

"""
    folder_resource_content(root, prefix, path; hidden=false, mime_types=nothing)

Read one file for a folder-backed resource. `path` is the decoded reserved
capture (it may contain `/`). `.`/`..`/backslash segments, NUL bytes, `:` on
Windows (drive/alternate-data-stream syntax), and (unless `hidden=true`)
dotfiles are rejected; the resolved target is checked with `realpath` against
the canonical root and read through a no-follow handle, so a symlink cannot
escape. Missing or unreadable files throw `MCP_RESOURCE_NOT_FOUND`, which
`read_resource` maps per era.
"""
function folder_resource_content(root::String, prefix::String, path::String;
                                 hidden::Bool=false, mime_types=nothing)
    uri = prefix * path
    invalid = isempty(path) || occursin('\0', path) || occursin('\\', path) ||
              (Sys.iswindows() && occursin(':', path))
    invalid && folder_not_found(uri)

    segments = split(path, '/'; keepempty=false)
    isempty(segments) && folder_not_found(uri)
    for segment in segments
        (segment == "." || segment == "..") && folder_not_found(uri)
        (!hidden && startswith(segment, ".")) && folder_not_found(uri)
    end

    real_root = try
        realpath(root)
    catch
        folder_not_found(uri)
    end
    real_file = try
        realpath(joinpath(real_root, segments...))
    catch
        folder_not_found(uri)
    end

    (is_within(real_root, real_file) && isfile(real_file)) || folder_not_found(uri)

    bytes = try
        read_folder_file(real_file)
    catch
        folder_not_found(uri)
    end
    mime = folder_mime(real_file, bytes, mime_types)
    return HTTP.Response(200, ["Content-Type" => mime], bytes)
end

"""
    register_resource_folder!(ctx, prefix, directory; name=nothing, description=nothing,
                              title=nothing, hidden=false, mime_types=nothing,
                              annotations=nothing, icons=nothing)

Register a resource template at `prefix * "{+path}"` serving regular files below
`directory`. The reserved capture spans `/`, so nested folders work; every read
is sanitized (see `folder_resource_content`). `mime_types` maps a file
extension (with or without the leading dot, matched case-insensitively) to a
MIME type; otherwise a built-in table and `HTTP.sniff` decide. `name` defaults
to the directory's basename.
"""
function register_resource_folder!(ctx::ServerContext, prefix::String, directory::String;
                                   name=nothing, description=nothing, title=nothing,
                                   hidden::Bool=false,
                                   mime_types::Union{Nothing,AbstractDict}=nothing,
                                   annotations=nothing, icons=nothing)
    isempty(prefix) && throw(ArgumentError("An MCP resource folder prefix cannot be empty"))
    occursin('{', prefix) && throw(ArgumentError(
        "MCP resource folder prefix `$prefix` cannot contain `{`; the helper appends `{+path}`"))
    isdir(directory) || throw(ArgumentError("MCP resource folder `$directory` is not a directory"))

    root = realpath(abspath(directory))
    uri = prefix * "{+path}"
    desc = isnothing(description) ? "Files served under $prefix" : string(description)
    folder_name = basename(root)
    wirename = isnothing(name) ? (isempty(folder_name) || folder_name == "/" ? "files" : folder_name) :
                                 string(name)

    handler = function (path::String)
        return folder_resource_content(root, prefix, path; hidden=hidden, mime_types=mime_types)
    end

    return register_resource!(ctx, uri, desc, handler;
                              name=wirename, title=title,
                              annotations=annotations, icons=icons)
end
