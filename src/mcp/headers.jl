# Standard MCP HTTP header lookup and Base64 sentinel decoding. Kept below the
# transports so sessions, specs, and dispatch can share the low-level parsing
# without importing `MCP.Transports`.

module Headers

using HTTP
using Base64: base64decode

using ..Errors: MCPRequestError, MCP_HEADER_MISMATCH

# ASCII case-insensitive comparison of wire names. Header names are ASCII and
# lookups run several times per request, so folding byte-by-byte replaces the
# `lowercase(String(key))` allocation this used to do for every header.
function header_name_equals(name::AbstractString, target::AbstractString) :: Bool
    ncodeunits(name) == ncodeunits(target) || return false
    @inbounds for index in 1:ncodeunits(target)
        lhs = codeunit(name, index)
        if UInt8('A') <= lhs <= UInt8('Z')
            lhs += 0x20
        end
        rhs = codeunit(target, index)
        if UInt8('A') <= rhs <= UInt8('Z')
            rhs += 0x20
        end
        lhs == rhs || return false
    end
    return true
end

"""
    mcp_standard_header(req, name) :: Union{Nothing,String,Symbol}

Case-insensitive lookup of a standard MCP request header. Returns `nothing` when
absent, `:invalid` when the header is duplicated or carries unsafe bytes, and the
whitespace-stripped value otherwise.
"""
function mcp_standard_header(req::HTTP.Request, name::String) :: Union{Nothing,String,Symbol}
    found = nothing
    for (key, value) in req.headers
        header_name_equals(key, name) || continue
        found === nothing || return :invalid
        found = value
    end
    found === nothing && return nothing
    value = String(strip(found))
    if !all(b -> 0x20 <= b <= 0x7e || b == UInt8('\t'), codeunits(value))
        return :invalid
    end
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
function decode_header_value(value::String) :: Union{Nothing,String}
    prefix = "=?base64?"
    suffix = "?="
    if startswith(value, prefix) && endswith(value, suffix) && length(value) >= length(prefix) + length(suffix)
        encoded = value[(length(prefix) + 1):(end - length(suffix))]
        if !occursin(r"^[A-Za-z0-9+/]+={0,2}$", encoded)
            return nothing
        end
        if length(encoded) % 4 != 0
            return nothing
        end
        decoded = try
            String(base64decode(encoded))
        catch
            # Invalid Base64 cannot represent a sentinel value.
            return nothing
        end
        if !all(isvalid, decoded)
            return nothing
        end
        return decoded
    end
    return value
end

# A required, well-formed standard header: throws the transport's
# `-32020` error when the header is missing, duplicated, or unsafe.
function required_header(req::HTTP.Request, name::String) :: String
    value = mcp_standard_header(req, name)
    if value === :invalid
        throw(MCPRequestError(MCP_HEADER_MISMATCH,
            "$name header is duplicated or contains unsafe characters"))
    end
    if isnothing(value)
        throw(MCPRequestError(MCP_HEADER_MISMATCH,
            "Missing required $name header"))
    end
    return String(value)
end

end # module Headers
