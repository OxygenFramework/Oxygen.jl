# JSON-RPC error results and the request-validation rules that raise them.
# Included into the `MCP` module by `../mcp.jl`.

function toolerror_result(error)::Dict{String,Any}
    return Dict{String,Any}(
        "content" => [Dict{String,Any}("type" => "text", "text" => sprint(showerror, error))],
        "isError" => true,
    )
end

function error_body(id, code::Int, message::String, data=nothing)::Dict{String,Any}
    error = Dict{String,Any}("code" => code, "message" => message)
    !isnothing(data) && (error["data"] = data)
    return Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "error" => error)
end

"""
    mcp_standard_header(req, name) :: Union{Nothing,String,Symbol}

Case-insensitive lookup of a standard MCP request header. Returns `nothing` when
absent, `:invalid` when the header is duplicated or carries unsafe bytes, and the
whitespace-stripped value otherwise.
"""
function mcp_standard_header(req::HTTP.Request, name::String)::Union{Nothing,String,Symbol}
    values = String[]
    target = lowercase(name)
    for (key, value) in req.headers
        lowercase(String(key)) == target || continue
        push!(values, String(value))
    end
    isempty(values) && return nothing
    length(values) > 1 && return :invalid
    value = String(strip(values[1]))
    all(b -> 0x20 <= b <= 0x7e || b == UInt8('\t'), codeunits(value)) || return :invalid
    return value
end

"""
    decode_header_value(value) :: Union{Nothing,String}

Decode a standard-header value per SEP-2243: a `=?base64?...?=` sentinel wraps a
Base64-encoded UTF-8 payload (used when the raw value is not header-safe). The
Base64 is validated strictly (canonical alphabet, correct padding, length a
multiple of four) and must decode to valid UTF-8. Returns `nothing` when the
value is a malformed sentinel; non-sentinel values are returned unchanged.
"""
function decode_header_value(value::String)::Union{Nothing,String}
    prefix = "=?base64?"
    suffix = "?="
    if startswith(value, prefix) && endswith(value, suffix) && length(value) >= length(prefix) + length(suffix)
        encoded = value[(length(prefix) + 1):(end - length(suffix))]
        occursin(r"^[A-Za-z0-9+/]+={0,2}$", encoded) || return nothing
        length(encoded) % 4 == 0 || return nothing
        decoded = try
            String(base64decode(encoded))
        catch
            return nothing
        end
        all(isvalid, decoded) || return nothing
        return decoded
    end
    return value
end

function check_origin(ctx::ServerContext, req::HTTP.Request)
    origin = HTTP.header(req, "Origin", nothing)
    (isnothing(origin) || isempty(origin)) && return nothing

    origin = String(origin)

    # Explicit allowlist always wins
    if origin in ctx.mcp.allowed_origins
        return nothing
    end

    # Same-host origins are permitted by default
    host = HTTP.header(req, "Host", nothing)
    if !isnothing(host)
        origin_host = try
            uri = HTTP.URI(origin)
            port = isnothing(uri.port) ? "" : ":" * string(uri.port)
            string(something(uri.host, "")) * port
        catch
            ""
        end
        if !isempty(origin_host) && origin_host == String(host)
            return nothing
        end
    end

    return HTTP.Response(403, "Forbidden")
end

"""
    request_era(req, method, params) :: Symbol

Classify a request by era. A request is modern iff its `params._meta` carries the
`io.modelcontextprotocol/protocolVersion` key, its method is `server/discover`
(modern-only), or — over HTTP — the `MCP-Protocol-Version` header names a modern
revision (era may be claimed by the headers alone). Everything else is legacy.
"""
function request_era(req::Union{Nothing,HTTP.Request}, method::String, params)::Symbol
    meta = get(params, META_KEY, nothing)
    if meta isa AbstractDict
        version = get(meta, META_PROTOCOL, nothing)
        version isa AbstractString && return :modern
    end

    method == "server/discover" && return :modern

    if req isa HTTP.Request
        header_version = mcp_standard_header(req, "MCP-Protocol-Version")
        header_version isa String && strip(header_version) in MODERN_VERSIONS && return :modern
    end

    return :legacy
end

"""
    validate_modern_request(ctx, req, method, params)

Enforce the modern-era (2026-07-28) per-request contract: a supported
`_meta.protocolVersion`, the required `_meta.clientCapabilities`, and — over
HTTP — mirrored standard headers (`MCP-Protocol-Version`, `Mcp-Method`, and
`Mcp-Name` for `tools/call`/`prompts/get`). Legacy requests skip all of this.
"""
function validate_modern_request(ctx::ServerContext, req::Union{Nothing,HTTP.Request}, method::String, params)
    meta = get(params, META_KEY, Dict{String,Any}())
    meta isa AbstractDict || (meta = Dict{String,Any}())

    body_version = get(meta, META_PROTOCOL, nothing)
    if !(body_version isa AbstractString) || isempty(body_version)
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_PROTOCOL"))
    end

    if !(String(body_version) in MODERN_VERSIONS)
        throw(MCPRequestError(MCP_UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version", Dict{String,Any}(
            "supported" => copy(SUPPORTED_VERSIONS),
            "requested" => String(body_version),
        )))
    end

    if !haskey(meta, META_CLIENT_CAPABILITIES)
        throw(MCPRequestError(MCP_INVALID_PARAMS, "Missing required _meta field: $META_CLIENT_CAPABILITIES"))
    end

    # The remaining checks are specific to the Streamable HTTP transport.
    req === nothing && return nothing

    header_version = mcp_standard_header(req, "MCP-Protocol-Version")
    header_version === :invalid && throw(MCPRequestError(MCP_HEADER_MISMATCH, "MCP-Protocol-Version header is duplicated or contains unsafe characters"))
    header_version === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH, "Missing required MCP-Protocol-Version header"))
    String(header_version) != String(body_version) && throw(MCPRequestError(MCP_HEADER_MISMATCH, "Header mismatch: MCP-Protocol-Version header value '$header_version' does not match body value '$body_version'"))

    header_method = mcp_standard_header(req, "Mcp-Method")
    header_method === :invalid && throw(MCPRequestError(MCP_HEADER_MISMATCH,"Mcp-Method header is duplicated or contains unsafe characters"))
    header_method === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH, "Missing required Mcp-Method header"))
    String(header_method) != method && throw(MCPRequestError(MCP_HEADER_MISMATCH, "Header mismatch: Mcp-Method header value '$header_method' does not match body value '$method'"))

    if method == "tools/call" || method == "prompts/get"

        header_name = mcp_standard_header(req, "Mcp-Name")
        header_name === :invalid && throw(MCPRequestError(MCP_HEADER_MISMATCH, "Mcp-Name header is duplicated or contains unsafe characters"))
        header_name === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH, "Missing required Mcp-Name header"))

        decoded = decode_header_value(String(header_name))
        decoded === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH, "Mcp-Name header carries a malformed Base64 sentinel value"))
        body_name = get(params, "name", nothing)
        
        if !(body_name isa AbstractString) || decoded != String(body_name)
            throw(MCPRequestError(MCP_HEADER_MISMATCH,
                "Header mismatch: Mcp-Name header value '$decoded' does not match body value '$(body_name)'"))
        end
    end

    return nothing
end
