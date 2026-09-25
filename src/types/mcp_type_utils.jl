module MCPTypeUtils

using ..CoreTypes: Nullable
using ..MCPTypes: MCPConfig, MCPMetadata

export parse_mcp_parameters, normalize_mcp_config, merge_mcp_configs, resolve_mcp_config

# Keys that identify a parameter or a metadata field must be Symbols. This keeps
# them comparable to reflected parameter names without the String->Symbol
# coercion that would silently mask a typo, and lets `get` work uniformly across
# `NamedTuple` and `Dict` metadata.
symbol_key(key::Symbol)::Symbol = key
symbol_key(key) = throw(ArgumentError("MCP metadata and parameter names must be Symbols, got a $(typeof(key)): $(repr(key))"))

mcp_string(value)::String = string(value)
mcp_string(::Nothing)::String = ""

# Normalize a collection of parameter declarations into an iterable of
# `(key, value)` pairs. Both `Dict` and `NamedTuple` are accepted, as is a vector
# of `Pair`s; keys must be Symbols. `nothing` yields an empty iterable.
function mcp_entries(params)
    if params === nothing
        return ()
    end
    if params isa AbstractDict || params isa NamedTuple
        return pairs(params)
    elseif params isa AbstractVector
        return params
    end
    throw(ArgumentError("Invalid parameter metadata: expected a Dict, NamedTuple, or vector of Pairs"))
end

"""
    parse_mcp_parameters(params) :: Dict{Symbol,String}

Parse a collection of parameter descriptions into a `Symbol => String` map.

`params` may be a `NamedTuple` or a `Dict` (with `Symbol` keys), or a vector of
`Pair`s. Each value is the parameter's human readable description. There is no
per-parameter wire-name override: use the `names` map in `mcp` metadata to
expose a parameter under a different JSON key. This is the single parser shared
by `@tool`/`tool` and by router/route `mcp` metadata so both accept the same
forms.
"""
function parse_mcp_parameters(params)
    descriptions = Dict{Symbol,String}()
    for (key, value) in mcp_entries(params)
        name = symbol_key(key)
        if value isa NamedTuple || value isa AbstractDict
            throw(ArgumentError(
                "Per-parameter `description`/`name` metadata is not supported; " *
                "pass a plain description and use `names` to override wire names"))
        end
        desc = mcp_string(value)
        if !isempty(desc)
            descriptions[name] = desc
        end
    end
    return descriptions
end

"""
    normalize_mcp_config(mcp) :: Nullable{MCPConfig}

Normalize the `mcp` metadata accepted by `router()` and route registration.
Each accepted container gets its own method below: `nothing` (meaning "not
specified", so the enclosing router's value is inherited), `false` (an
explicitly disabled config), `true` (an enabled config with defaults), a
`String` (an enabled config whose description is the string), and a
`NamedTuple`/`Dict` of overrides. Any other value throws.

The override container (`NamedTuple` or `Dict`) must use `Symbol` keys; the two
are normalized by the same helper.
"""
normalize_mcp_config(::Nothing)::Nullable{MCPConfig} = nothing
normalize_mcp_config(mcp::Bool)::Nullable{MCPConfig} = MCPConfig(enabled=mcp)
# A bare string is a description shorthand. This also makes the natural
# single-field form `mcp = (description = "...")` work, since Julia parses a
# one-element `(key = value)` as an assignment rather than a NamedTuple.
normalize_mcp_config(mcp::AbstractString)::Nullable{MCPConfig} =
    MCPConfig(enabled=true, description=String(mcp))
normalize_mcp_config(mcp::NamedTuple)::Nullable{MCPConfig} = normalize_mcp_overrides(mcp)
normalize_mcp_config(mcp::AbstractDict)::Nullable{MCPConfig} = normalize_mcp_overrides(mcp)
normalize_mcp_config(mcp)::Nullable{MCPConfig} = throw(ArgumentError(
    "Invalid `mcp` metadata: expected true, false, a description string, a NamedTuple, or a Dict"))

# Parse the `description`/`parameters`/`names`/`name` overrides carried by a
# `NamedTuple` or `Dict`, enforcing the symbols-only key policy.
function normalize_mcp_overrides(mcp::Union{NamedTuple,AbstractDict})
    for key in keys(mcp)
        symbol_key(key)
    end

    description = mcp_string(get(mcp, :description, ""))
    parameters = parse_mcp_parameters(get(mcp, :parameters, nothing))

    names = Dict{Symbol,String}()
    for (key, value) in mcp_entries(get(mcp, :names, nothing))
        names[symbol_key(key)] = string(value)
    end

    toolname = get(mcp, :name, nothing)
    return MCPConfig(
        enabled = true,
        description = description,
        parameters = parameters,
        names = names,
        toolname = toolname === nothing ? nothing : string(toolname),
    )
end

# Combine an enclosing router's config with a route's config, letting the route
# win. `group` carries the router description so it can prefix the final text.
function merge_mcp_configs(outer::MCPConfig, route::MCPConfig)::MCPConfig
    return MCPConfig(
        enabled = route.enabled,
        description = route.description,
        group = isempty(outer.description) ? outer.group : outer.description,
        parameters = merge(outer.parameters, route.parameters),
        names = merge(outer.names, route.names),
        toolname = route.toolname,
    )
end

"""
    resolve_mcp_config(outer, route) :: Nullable{MCPConfig}

Determine the effective MCP metadata for a route. A disabled enclosing router is
authoritative: inner (route) metadata cannot re-enable it. An explicitly disabled
route (`mcp = false`) excludes the route. Otherwise the route's values override
the router's, with parameter descriptions/wire names merged.
"""
function resolve_mcp_config(outer::Nullable{MCPConfig}, route::Nullable{MCPConfig})::Nullable{MCPConfig}
    # A disabled router excludes its whole group; a route cannot opt back in.
    if outer !== nothing && !outer.enabled
        return nothing
    end

    if route === nothing
        if outer === nothing
            return nothing
        end
        # A router-level `name` would collide across every route, so only a
        # route may set the tool name.
        return isnothing(outer.toolname) ? outer : MCPConfig(
            enabled = outer.enabled, description = outer.description, group = outer.group,
            parameters = outer.parameters, names = outer.names, toolname = nothing)
    end
    if !route.enabled
        return nothing
    end
    if outer === nothing
        return route
    end
    return merge_mcp_configs(outer, route)
end

end
