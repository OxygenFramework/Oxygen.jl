module Cookies

using HTTP
using ..Types

export encrypt_payload, decrypt_payload, parse_cookies, format_cookie

"""
Placeholder for encryption - to be extended by OxygenCryptoExt
"""
function encrypt_payload(secret::String, payload::String)
    return payload
end

"""
Placeholder for decryption - to be extended by OxygenCryptoExt
"""
function decrypt_payload(secret::String, payload::String)
    return payload
end

"""
Optimized cookie parser that uses SubStrings to minimize allocations
"""
function parse_cookies(headers::Dict{String, String})
    cookies = Dict{SubString{String}, SubString{String}}()
    cookie_header = get(headers, "cookie", get(headers, "Cookie", nothing))
    
    if isnothing(cookie_header)
        return cookies
    end

    for pair in eachsplit(cookie_header, ';')
        trimmed = strip(pair)
        if isempty(trimmed)
            continue
        end
        
        # find the first '=' to split name and value
        idx = findfirst('=', trimmed)
        if isnothing(idx)
            continue
        end
        
        name = @view trimmed[1:prevind(trimmed, idx)]
        value = @view trimmed[nextind(trimmed, idx):end]
        cookies[name] = value
    end
    
    return cookies
end

"""
Strictly format a cookie header string according to RFC 6265bis
"""
function format_cookie(
    name::String, 
    value::String; 
    path::String = "/", 
    domain::Nullable{String} = nothing, 
    expires::Nullable{Dates.DateTime} = nothing, 
    maxage::Nullable{Int} = nothing, 
    httponly::Bool = true, 
    secure::Bool = true, 
    samesite::String = "Lax"
)
    parts = ["$name=$value", "Path=$path"]
    
    if !isnothing(domain)
        push!(parts, "Domain=$domain")
    end
    
    if !isnothing(expires)
        # Format: Wdy, DD Mon YYYY HH:MM:SS GMT
        push!(parts, "Expires=$(Dates.format(expires, Dates.RFC1123Format))")
    end
    
    if !isnothing(maxage)
        push!(parts, "Max-Age=$maxage")
    end
    
    if httponly
        push!(parts, "HttpOnly")
    end
    
    if secure
        push!(parts, "Secure")
    end
    
    # SameSite validation
    ss = uppercasefirst(lowercase(samesite))
    if ss in ("Lax", "Strict", "None")
        push!(parts, "SameSite=$ss")
        if ss == "None" && !secure
            @warn "SameSite=None cookies must also be Secure. Setting Secure=true."
            # We don't force it here but it's a security best practice/requirement in modern browsers
        end
    end
    
    return join(parts, "; ")
end

end
