# Behavioral hooks for the modern (2026-07-28) revision. The profile itself is
# declared in `v2026_07_28.jl`; these methods run during request processing and
# are included after the version registry exists (they read `SUPPORTED_VERSIONS`
# and the other derived constants). Included into `MCP.Specs` by `../specs.jl`.

"""
    validate_modern_request(ctx, req, method, params)

Enforce the modern-era (2026-07-28) per-request contract: a supported
`_meta.protocolVersion`, the required `_meta.clientCapabilities`, and, over
HTTP, mirrored standard headers (`MCP-Protocol-Version`, `Mcp-Method`, and
`Mcp-Name` for `tools/call`/`prompts/get`/`resources/read`). Legacy requests
skip all of this.
"""
function validate_modern_request(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, method::String, params)
    meta = get(params, META_KEY, Dict{String,Any}())
    if !(meta isa AbstractDict)
        meta = Dict{String,Any}()
    end

    body_version = get(meta, META_PROTOCOL, nothing)
    if !(body_version isa AbstractString) || isempty(body_version)
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_PROTOCOL"))
    end

    body_spec = spec_from_version(String(body_version))
    if isnothing(body_spec) || !is_modern(body_spec)
        throw(MCPRequestError(MCP_UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version", Dict{String,Any}(
            "supported" => copy(SUPPORTED_VERSIONS),
            "requested" => String(body_version),
        )))
    end

    if !haskey(meta, META_CLIENT_CAPABILITIES)
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_CLIENT_CAPABILITIES"))
    end

    # The remaining checks are specific to the Streamable HTTP transport.
    if isnothing(req)
        return nothing
    end

    header_version = required_header(req, "MCP-Protocol-Version")
    if String(header_version) != String(body_version)
        throw(MCPRequestError(MCP_HEADER_MISMATCH,
            "Header mismatch: MCP-Protocol-Version header value '$header_version' does not match body value '$body_version'"))
    end

    header_method = required_header(req, "Mcp-Method")
    if String(header_method) != method
        throw(MCPRequestError(MCP_HEADER_MISMATCH,
            "Header mismatch: Mcp-Method header value '$header_method' does not match body value '$method'"))
    end

    # `Mcp-Name` mirrors the body field that addresses the request: the name for
    # tools/prompts, the URI for resources.
    source = if method == "tools/call" || method == "prompts/get"
        "name"
    elseif method == "resources/read"
        "uri"
    else
        nothing
    end

    if !isnothing(source)
        decoded = decode_header_value(required_header(req, "Mcp-Name"))
        if isnothing(decoded)
            throw(MCPRequestError(MCP_HEADER_MISMATCH,
                "Mcp-Name header carries a malformed Base64 sentinel value"))
        end
        body_name = get(params, source, nothing)

        if !(body_name isa AbstractString) || decoded != String(body_name)
            throw(MCPRequestError(MCP_HEADER_MISMATCH,
                "Header mismatch: Mcp-Name header value '$decoded' does not match body value '$(body_name)'"))
        end
    end

    return nothing
end

validate_request(::Val{:v2026_07_28}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
                 method::String, params) = validate_modern_request(ctx, req, method, params)

result_envelope(::Val{:v2026_07_28}, ctx::ServerContext, result) = modern_envelope(ctx, result)

function with_cache_hints(::Val{:v2026_07_28}, result; scope::String="public")
    result["ttlMs"] = LIST_TTL_MS
    result["cacheScope"] = scope
    return result
end
