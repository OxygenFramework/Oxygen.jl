module MCPTypeUtils

using ..CoreTypes: Nullable
using ..MCPTypes: MCPConfig, MCPMetadata

export parse_mcp_parameters, normalize_mcp_config, merge_mcp_configs, resolve_mcp_config

# Pull a key out of user supplied metadata (NamedTuple or Dict with Symbol or
# String keys), falling back to `default`.
function _mcp_get(mcp, key::Symbol, default)
    if mcp isa NamedTuple
        return get(mcp, key, default)
    end
    if haskey(mcp, key)
        return mcp[key]
    end
    stringkey = String(key)
    if haskey(mcp, stringkey)
        return mcp[stringkey]
    end
    return default
end

_mcp_string(value)::String = string(value)
_mcp_string(::Nothing)::String = ""

# Normalize a collection of parameter declarations into an iterable of
# `(key, value)` pairs. Both `Dict` (Symbol or String keys) and `NamedTuple`
# are accepted, as is a vector of `Pair`s. `nothing` yields an empty iterable.
function _mcp_entries(params)
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
    parse_mcp_parameters(params) :: (Dict{Symbol,String}, Dict{Symbol,String})

Parse a collection of parameter declarations into `(descriptions, names)`.

`params` may be a `Dict` (Symbol or String keys), a `NamedTuple`, or a vector of
`Pair`s. Each value is either a plain description (anything string-convertible)
or a `NamedTuple`/`Dict` carrying a `description` and/or a `name` wire-name
override. This is the single parser shared by `@tool`/`tool` and by router/route
`mcp` metadata so both accept the same forms.
"""
function parse_mcp_parameters(params)
    descriptions = Dict{Symbol,String}()
    names = Dict{Symbol,String}()
    for (key, value) in _mcp_entries(params)
        name = Symbol(key)
        if value isa NamedTuple || value isa AbstractDict
            desc = _mcp_string(_mcp_get(value, :description, ""))
            wirename = _mcp_get(value, :name, nothing)
            if !isempty(desc)
                descriptions[name] = desc
            end
            if wirename !== nothing
                names[name] = string(wirename)
            end
        else
            desc = _mcp_string(value)
            if !isempty(desc)
                descriptions[name] = desc
            end
        end
    end
    return descriptions, names
end

"""
    normalize_mcp_config(mcp) :: Nullable{MCPConfig}

Normalize the `mcp` metadata accepted by `router()` and route registration.
Returns `nothing` when the metadata is `nothing` (meaning "not specified", so
the enclosing router's value is inherited), an explicitly disabled config for
`false`, an enabled config with defaults for `true`, an enabled config with a
description for a `String`, and an enabled config for a `NamedTuple`/`Dict` of
overrides. Any other value throws.
"""
function normalize_mcp_config(mcp)::Nullable{MCPConfig}
    if mcp === nothing
        return nothing
    end
    if mcp === false
        return MCPConfig(enabled=false)
    end
    if mcp === true
        return MCPConfig()
    end
    # A bare string is a description shorthand. This also makes the natural
    # single-field form `mcp = (description = "...")` work, since Julia parses a
    # one-element `(key = value)` as an assignment rather than a NamedTuple.
    if mcp isa AbstractString
        return MCPConfig(enabled=true, description=String(mcp))
    end
    if !(mcp isa NamedTuple || mcp isa AbstractDict)
        throw(ArgumentError("Invalid `mcp` metadata: expected true, false, a description string, a NamedTuple, or a Dict"))
    end

    description = _mcp_string(_mcp_get(mcp, :description, ""))
    parameters, names = parse_mcp_parameters(_mcp_get(mcp, :parameters, nothing))

    rawnames = _mcp_get(mcp, :names, nothing)
    for (key, value) in _mcp_entries(rawnames)
        names[Symbol(key)] = string(value)
    end

    toolname = _mcp_get(mcp, :name, nothing)
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
