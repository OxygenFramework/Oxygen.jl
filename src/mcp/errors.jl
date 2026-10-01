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
    request_claim(req, method, params) :: Union{Nothing,Val,Symbol}

The modern-era claim of a request, before the session's negotiated version is
consulted. Returns the claimed `Val` revision when `params._meta` names a
supported modern revision, the method is `server/discover` (modern-only), or —
over HTTP — the `MCP-Protocol-Version` header names a modern revision.
`:unsupported` is returned when `_meta.protocolVersion` is a string naming a
revision this server cannot serve as a modern request; `nothing` means the
request claims nothing modern (a legacy request). See `request_spec` for the
claim combined with the negotiated legacy fallback.
"""
function request_claim(req::Union{Nothing,HTTP.Request}, method::String, params)
    meta = get(params, META_KEY, nothing)
    if meta isa AbstractDict
        version = get(meta, META_PROTOCOL, nothing)
        if version isa AbstractString
            spec = spec_from_version(String(version))
            return (spec !== nothing && is_modern(spec)) ? spec : :unsupported
        end
    end

    method == "server/discover" && return LATEST_MODERN_SPEC

    if req isa HTTP.Request
        header_version = mcp_standard_header(req, "MCP-Protocol-Version")
        if header_version isa String
            header_spec = spec_from_version(strip(header_version))
            header_spec !== nothing && is_modern(header_spec) && return header_spec
        end
    end

    return nothing
end

# A required, well-formed standard header: throws the transport's
# `-32020` error when the header is missing, duplicated, or unsafe.
function required_header(req::HTTP.Request, name::String)::String
    value = mcp_standard_header(req, name)
    value === :invalid && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "$name header is duplicated or contains unsafe characters"))
    value === nothing && throw(MCPRequestError(MCP_HEADER_MISMATCH,
        "Missing required $name header"))
    return String(value)
end

# The modern-era per-request contract (`validate_modern_request`) is a revision
# delta and lives in `specs/v2026_07_28.jl`; this file keeps only the shared
# header and error helpers it builds on.
