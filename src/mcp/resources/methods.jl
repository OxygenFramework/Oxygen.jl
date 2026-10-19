# `resources/list`, `resources/templates/list`, and `resources/read`.
# Included into `MCP.Resources` by `../resources.jl`.

# ----------------------------------------------------------------------------
# Methods
# ----------------------------------------------------------------------------

# Static entries and template entries share the same wire fields except for the
# identifier key (`uri` vs `uriTemplate`). `icons` postdate the oldest legacy
# revisions, so the revision gates it off for clients that may reject unknown
# fields; passing `nothing` keeps it for direct callers.
function resource_entry(resource::MCPResource;
                        spec::Union{Nothing,Val}=nothing)::Dict{String,Any}
    entry = Dict{String,Any}(
        "name" => resource.name,
        "description" => resource.description,
    )
    entry[resource.template ? "uriTemplate" : "uri"] = resource.uri
    if !isnothing(resource.title)
        entry["title"] = resource.title
    end
    if !isnothing(resource.mime_type)
        entry["mimeType"] = resource.mime_type
    end
    if !isnothing(resource.size)
        entry["size"] = resource.size
    end
    if !isnothing(resource.annotations)
        entry["annotations"] = resource.annotations
    end
    if (isnothing(spec) || shows_resource_icons(spec)) && !isnothing(resource.icons)
        entry["icons"] = resource.icons
    end
    return entry
end

function resource_list(entries::Dict{String,MCPResource}, key::String;
                       spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    items = [resource_entry(entries[uri]; spec=spec) for uri in sort(collect(keys(entries)))]
    return list_result(key, items; spec=spec)
end

function resources_list(ctx::ServerContext; spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    return resource_list(ctx.mcp.resources, "resources"; spec=spec)
end

function resource_templates_list(ctx::ServerContext; spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    return resource_list(ctx.mcp.resource_templates, "resourceTemplates"; spec=spec)
end

# Resolve a requested URI to its resource. Exact registrations win over
# templates; templates are scanned in sorted order so overlapping templates
# resolve deterministically.
function resolve_resource(ctx::ServerContext, uri::String)
    resource = get(ctx.mcp.resources, uri, nothing)
    if !isnothing(resource)
        return resource, Dict{String,Any}()
    end

    for template in sort(collect(keys(ctx.mcp.resource_templates)))
        candidate = ctx.mcp.resource_templates[template]
        arguments = match_template(candidate, uri)
        if !isnothing(arguments)
            return candidate, arguments
        end
    end
    return nothing
end

function read_resource(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, id, params;
                       spec::Val=LATEST_LEGACY_SPEC)::Tuple{Dict{String,Any},Int}
    body_uri = get(params, "uri", nothing)
    if !(body_uri isa AbstractString) || isempty(body_uri)
        return error_body(id, MCP_INVALID_PARAMS, "Missing resource URI"), 200
    end

    uri = String(body_uri)
    resolved = resolve_resource(ctx, uri)
    if isnothing(resolved)
        # The modern revision folded not-found into -32602; the legacy
        # revisions defined the dedicated -32002.
        return error_body(id, not_found_code(spec), "Resource not found",
                          Dict{String,Any}("uri" => uri)), 200
    end

    resource, arguments = resolved
    try
        value = invoke_registered(ctx, req, resource, arguments)
        result = with_cache_hints(spec, resource_result(resource, uri, value); scope="private")
        return result_response(ctx, id, result; spec=spec)
    catch error
        if error isa MCPRequestError
            # A handler that cannot resolve its URI (e.g. the folder helper)
            # throws the legacy not-found code; translate it like the
            # unresolved-URI path above.
            code = error.code == not_found_code(LATEST_LEGACY_SPEC) ?
                not_found_code(spec) : error.code
            return request_error_body(id, error, code), 200
        end
        return error_body(id, MCP_INTERNAL_ERROR, sprint(showerror, error)), 200
    end
end

# ----------------------------------------------------------------------------
# Method routing
# ----------------------------------------------------------------------------

# Served in every revision; the list/read shaping differences (icons, cache
# hints, not-found code) live behind the strategy interface.
handle_method(spec::Val, ::Val{:resources_list}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session=nothing) =
    result_response(ctx, id, resources_list(ctx; spec=spec); spec=spec)

handle_method(spec::Val, ::Val{:resources_templates_list}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session=nothing) =
    result_response(ctx, id, resource_templates_list(ctx; spec=spec); spec=spec)

handle_method(spec::Val, ::Val{:resources_read}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session=nothing) =
    read_resource(ctx, req, id, params; spec=spec)

