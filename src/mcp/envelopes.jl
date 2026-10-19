# Reserved `_meta` keys, result-envelope constructors, and cache-hint constants.
# Shared by the spec strategies and the serialization pipeline; deliberately
# depends only on `MCP.Errors`/`AppContext`, never on a domain module.

module Envelopes

using ...AppContext: ServerContext

# Reserved `_meta` keys.
const META_KEY = "_meta"
const META_PROTOCOL = "io.modelcontextprotocol/protocolVersion"
const META_CLIENT_INFO = "io.modelcontextprotocol/clientInfo"
const META_CLIENT_CAPABILITIES = "io.modelcontextprotocol/clientCapabilities"
const META_SERVER_INFO = "io.modelcontextprotocol/serverInfo"

# Cache hints for list/discovery results (SEP-2549). Supported versions and
# instructions are static, but discovery's capabilities are derived from the
# mutable tool/prompt/resource registries, so a cached discovery response goes
# stale the moment anything is registered. Both hints are therefore 0 (no
# caching); `list_changed` notifications cover the list case.
const DISCOVER_TTL_MS = 0
const LIST_TTL_MS = 0

"""
    server_info(ctx) :: Dict

The server identity object carried by the legacy `initialize` result
(`serverInfo`) and every modern result (`io.modelcontextprotocol/serverInfo` in
`_meta`). The optional `description` is present only when configured through
`mcp_server_description`.
"""
function server_info(ctx::ServerContext)::Dict{String,Any}
    info = Dict{String,Any}(
        "name" => ctx.mcp.server_name[],
        "version" => ctx.mcp.server_version[],
    )
    if !isnothing(ctx.mcp.server_description[])
        info["description"] = ctx.mcp.server_description[]
    end
    return info
end

"""
    modern_envelope(ctx, result) :: Dict

Apply the modern-era result envelope to `result`: every modern result MUST carry
`resultType` (`"complete"`) and SHOULD identify the server via
`io.modelcontextprotocol/serverInfo` in the result `_meta`. Legacy results are
left untouched (legacy clients choke on unexpected `resultType`/`ttlMs`).
"""
function modern_envelope(ctx::ServerContext, result::Dict{String,Any})::Dict{String,Any}
    result["resultType"] = "complete"

    meta = get(result, META_KEY, nothing)
    if !(meta isa AbstractDict)
        meta = Dict{String,Any}()
    end
    meta[META_SERVER_INFO] = server_info(ctx)
    result[META_KEY] = meta
    return result
end

end # module Envelopes
