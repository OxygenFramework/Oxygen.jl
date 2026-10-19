# Capability discovery, legacy initialization, and the methods that expose them.
# Included into `MCP` by the `MCP.Discovery` submodule file.

module Discovery

using HTTP

using ...AppContext: ServerContext

using ..Envelopes: DISCOVER_TTL_MS, server_info
using ..Notifications: has_resources
using ..Sessions: MCPSession, set_handshake!
using ..Serialization: result_response
using ..Specs: SUPPORTED_VERSIONS, negotiate_version

import ..Dispatch: handle_method

# Capabilities advertised in both `server/discover` and `initialize`: tools are
# always served; prompts and resources only when at least one is registered.
# Registration functions push list-changed notifications, so every advertised
# `listChanged` flag is truthful; resources also support subscriptions.
function server_capabilities(ctx::ServerContext)::Dict{String,Any}
    capabilities = Dict{String,Any}(
        "tools" => Dict{String,Any}("listChanged" => true)
    )
    if !isempty(ctx.mcp.prompts)
        capabilities["prompts"] = Dict{String,Any}("listChanged" => true)
    end
    if has_resources(ctx)
        capabilities["resources"] = Dict{String,Any}("subscribe" => true, "listChanged" => true)
    end
    return capabilities
end

function discover_result(ctx::ServerContext)::Dict{String,Any}
    result = Dict{String,Any}(
        "supportedVersions" => copy(SUPPORTED_VERSIONS),
        "capabilities" => server_capabilities(ctx),
        "ttlMs" => DISCOVER_TTL_MS,
        "cacheScope" => "public",
    )
    if !isnothing(ctx.mcp.instructions)
        result["instructions"] = ctx.mcp.instructions
    end
    return result
end

"""
    initialize_result(ctx, params; session=nothing) :: Dict

Build the legacy `initialize` response. The client's version is echoed when
supported, otherwise the latest legacy revision is offered; the negotiated
version is remembered on `session` (or on the context-wide anonymous state for
stdio and header-less HTTP clients) for later feature gating.
"""
function initialize_result(ctx::ServerContext, params; session::Union{Nothing,MCPSession}=nothing)::Dict{String,Any}
    client_version = get(params, "protocolVersion", nothing)
    if !(client_version isa AbstractString)
        client_version = nothing
    end
    negotiated = negotiate_version(client_version)
    # A header-less initialize arms the context-wide anonymous state; a session
    # is armed on itself. Delivery additionally requires a completed handshake.
    set_handshake!(ctx, session, negotiated)

    result = Dict{String,Any}(
        "protocolVersion" => negotiated,
        "capabilities" => server_capabilities(ctx),
        "serverInfo" => server_info(ctx),
    )
    if !isnothing(ctx.mcp.instructions)
        result["instructions"] = ctx.mcp.instructions
    end
    return result
end

# Discovery methods, declared with the capability and version code above.

function handle_method(
    spec::Val, 
    ::Val{:initialize}, 
    ctx::ServerContext, 
    req::Union{Nothing,HTTP.Request},
    id, 
    params, 
    raw::String; 
    session::Union{Nothing,MCPSession}=nothing)
    
    return result_response(ctx, id, initialize_result(ctx, params; session=session); spec=spec)
end

function handle_method(
    spec::Val, 
    ::Val{:server_discover}, 
    ctx::ServerContext, 
    req::Union{Nothing,HTTP.Request}, 
    id, 
    params, 
    raw::String; 
    session::Union{Nothing,MCPSession}=nothing)
    
    return result_response(ctx, id, discover_result(ctx); spec=spec)
end

function handle_method(
    spec::Val, 
    ::Val{:ping}, 
    ctx::ServerContext, 
    req::Union{Nothing,HTTP.Request},
    id, 
    params, 
    raw::String; 
    session::Union{Nothing,MCPSession}=nothing)
    
    return result_response(ctx, id, Dict{String,Any}(); spec=spec)
end

end # module Discovery
