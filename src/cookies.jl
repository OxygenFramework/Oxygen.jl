module Cookies

using HTTP
using Dates
using ..Types

export encrypt_payload, decrypt_payload, parse_cookies, format_cookie, get_cookie, set_cookie!, set!, load_cookie_settings!,
    storesession!, prunesessions!

# ============================================================================
# SECTION 1: Extension Hooks (Encryption)
# ============================================================================

"""
Placeholder for encryption - to be extended by OxygenCryptoExt
"""
function encrypt_payload(secret, payload)
    return payload
end

"""
Placeholder for decryption - to be extended by OxygenCryptoExt
"""
function decrypt_payload(secret, payload)
    return payload
end

# ============================================================================
# SECTION 2: Internal Normalization & Validation
# ============================================================================

"""
    _normalize_attribute_name(name::Union{String, Symbol})

Normalizes the attribute name to standard lowercase symbols.
"""
function _normalize_attribute_name(name::Union{String, Symbol}) :: Symbol
    n = replace(lowercase(string(name)), "_" => "")
    n == "path" && return :path
    n == "secure" && return :secure
    n == "httponly" && return :httponly
    n == "domain" && return :domain
    n == "expires" && return :expires
    n == "maxage" && return :maxage
    n == "samesite" && return :samesite
    n == "max-age" && return :maxage
    n == "http-only" && return :httponly
    n == "same-site" && return :samesite
    n == "secretkey" && return :secret_key
    n == "maxcookiesize" && return :max_cookie_size
    
    return n |> Symbol
end

"""
Helper to convert SameSite string to standard string
"""
function _samesite_to_mode(val::String) :: Union{String, Nothing}
    val_lower = lowercase(strip(val))
    val_lower == "lax" && return "Lax"
    val_lower == "strict" && return "Strict"
    val_lower == "none" && return "None"
    nothing
end

"""
Helper to normalize expires value from various sources
"""
function _normalize_expires(val::Any) :: Union{Dates.DateTime, Nothing}
    if isnothing(val) || val isa Dates.DateTime
        return val
    end

    if !isa(val, AbstractString)
        throw(ArgumentError("expires: expected String or DateTime, got $(typeof(val))"))
    end
  
    # Try RFC 2822: "Wed, 09 Jun 2025 10:18:14 GMT"
    if occursin(r"^[A-Za-z]{3},\s+\d{2}\s+[A-Za-z]{3}\s+\d{4}\s+\d{2}:\d{2}:\d{2}\s+[A-Z]{3}$", val)
        try return Dates.DateTime(val, dateformat"e, dd u yyyy HH:MM:SS \G\M\T") catch; end
    end
  
    # Try ISO 8601: "2025-06-09T10:18:14Z"
    if occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", val)
        try return Dates.DateTime(val, dateformat"yyyy-mm-ddTHH:MM:SS\Z") catch; end
    end
  
    # Try Unix timestamp
    if occursin(r"^\d+$", val)
        try return Dates.unix2datetime(parse(Int64, val)) catch; end
    end
  
    throw(ArgumentError("expires: cannot parse '$val' as DateTime"))
end

"""
Helper to normalize domain strings
"""
function _normalize_domain(val::Any) :: String
    if !isa(val, AbstractString)
        throw(ArgumentError("domain: expected String, got $(typeof(val))"))
    end

    d = strip(String(val))
    if isempty(d)
        throw(ArgumentError("domain: cannot be empty"))
    end

    if !occursin(r"^[A-Za-z0-9\.-]+$", d) || occursin(':', d)
        throw(ArgumentError("domain: contains invalid characters: \"$val\""))
    end

    return lowercase(d)
end

function _normalize_bool(val::Any, name::String) :: Bool
    if val isa Bool
        return val
    elseif val isa AbstractString
        v = lowercase(strip(val))
        if v in ("true", "1", "yes", "on")
            return true
        elseif v in ("false", "0", "no", "off")
            return false
        end
    elseif val isa Number
        return val != 0
    end
    throw(ArgumentError("$name: cannot parse '$val' as Bool"))
end

function _normalize_maxage(val::Any) :: Tuple{Union{Int, Nothing}, Bool, Union{Dates.DateTime, Nothing}}
    mv = if val isa AbstractString
        tryparse(Int, val)
    elseif val isa Number
        Int(val)
    else
        nothing
    end

    if isnothing(mv) && val isa AbstractString
        throw(ArgumentError("max_age: cannot parse '$val' as integer"))
    end

    if mv == 0
        return (0, true, Dates.DateTime(1970, 1, 1))
    else
        return (mv, false, nothing)
    end
end

# ============================================================================
# SECTION 3: Parsing & Formatting (The Engine)
# ============================================================================

"""
Internal helper to extract a single cookie value from a header string lazily.
Works with SubString views to minimize allocations.
"""
function _extract_value_from_header(header_value::AbstractString, target_key::String) :: Union{SubString{String}, Nothing}
    target_lower = lowercase(target_key)
    for pair in eachsplit(header_value, ';')
        trimmed = strip(pair)
        idx = findfirst('=', trimmed)
        
        name_view = isnothing(idx) ? trimmed : strip(@view trimmed[begin:prevind(trimmed, idx)])
        
        if lowercase(name_view) == target_lower
            if isnothing(idx)
                return SubString("")
            end
            # Extract, strip whitespace, then strip surrounding quotes if balanced
            val_view = strip(@view trimmed[nextind(trimmed, idx):end])
            if length(val_view) >= 2 && val_view[begin] == '"' && val_view[end] == '"'
                return @view val_view[nextind(val_view, begin):prevind(val_view, end)]
            end
            return val_view
        end
    end
    return nothing
end

"""
Optimized cookie parser that uses SubStrings to minimize allocations.
Strips surrounding quotes from values according to RFC 6265.
"""
function parse_cookies(headers::Union{Dict, Vector{Pair{String, String}}, HTTP.Headers})
    cookies = Dict{SubString{String}, SubString{String}}()
    
    # Extract cookie header - account for both Request (Cookie) and Response (Set-Cookie)
    cookie_header = ""
    if headers isa Dict
        cookie_header = Base.get(headers, "cookie", Base.get(headers, "Cookie", ""))
    else
        for (k, v) in headers
            if lowercase(k) == "cookie"
                cookie_header = v
                break
            end
        end
    end

    if isempty(cookie_header)
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
            # RFC 6265: Cookie without '=' is treated as name with empty value
            cookies[trimmed] = ""
            continue
        end
        
        name = strip(@view trimmed[begin:prevind(trimmed, idx)])
        value = strip(@view trimmed[nextind(trimmed, idx):end])
        
        # Strip surrounding quotes if balanced (RFC 6265)
        if length(value) >= 2 && value[begin] == '"' && value[end] == '"'
            value = @view value[nextind(value, begin):prevind(value, end)]
        end
        
        cookies[name] = value
    end
    
    return cookies
end

function parse_cookies(req::HTTP.Request)
    return parse_cookies(req.headers)
end

function parse_cookies(res::HTTP.Response)
    # Set-Cookie is different as it can have name=value; attr1=val1; ...
    cookies = Dict{SubString{String}, SubString{String}}()
    for (k, v) in res.headers
        if lowercase(k) == "set-cookie"
            # find the first ';' which separates the cookie-pair from attributes
            semi_idx = findfirst(';', v)
            pair_view = isnothing(semi_idx) ? SubString(v) : @view v[begin:prevind(v, semi_idx)]
            
            eq_idx = findfirst('=', pair_view)
            if !isnothing(eq_idx)
                name = strip(@view pair_view[begin:prevind(pair_view, eq_idx)])
                val = strip(@view pair_view[nextind(pair_view, eq_idx):end])
                
                # Strip internal quotes if balanced (RFC 6265)
                if length(val) >= 2 && val[begin] == '"' && val[end] == '"'
                    val = @view val[nextind(val, begin):prevind(val, end)]
                end
                
                cookies[name] = val
            end
        end
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
        # Basic domain validation (no spaces, no ports)
        if occursin(' ', domain) || occursin(':', domain)
            throw(ArgumentError("Invalid domain: $domain"))
        end
        push!(parts, "Domain=$(lowercase(strip(domain)))")
    end
    
    # Handle Max-Age=0 and convert to past Expires for better reliability
    if !isnothing(maxage)
        push!(parts, "Max-Age=$maxage")
        if maxage == 0
            # Set expires to epoch
            push!(parts, "Expires=Thu, 01 Jan 1970 00:00:00 GMT")
        end
    end

    if isnothing(maxage) && !isnothing(expires)
        push!(parts, "Expires=$(Dates.format(expires, Dates.RFC1123Format)) GMT")
    end
    
    if httponly
        push!(parts, "HttpOnly")
    end
    
    # SameSite validation
    ss = uppercasefirst(lowercase(strip(samesite)))
    if ss == "None" 
        # SameSite=None cookies must be Secure
        if !secure
            @warn "SameSite=None cookies must also be Secure. Setting Secure=true."
            secure = true
        end
        push!(parts, "SameSite=None")
    elseif ss in ("Lax", "Strict")
        push!(parts, "SameSite=$ss")
    end

    if secure
        push!(parts, "Secure")
    end
    
    return join(parts, "; ")
end

# ============================================================================
# SECTION 4: Public API (Get/Set)
# ============================================================================

"""
Internal lazy lookup for a cookie value across all headers.
Handles both Request (Cookie) and Response (Set-Cookie).
"""
function _get_cookie_lazy(headers::Any, target_name::String) :: Union{SubString{String}, Nothing}
    tn_lower = lowercase(target_name)
    
    if headers isa Dict
        # Check Cookie header (Request)
        cookie_val = Base.get(headers, "cookie", Base.get(headers, "Cookie", nothing))
        if !isnothing(cookie_val)
            res = _extract_value_from_header(cookie_val, target_name)
            !isnothing(res) && return res
        end
        
        # Check Set-Cookie (Response) - unlikely in a Dict but possible
        set_cookie_val = Base.get(headers, "set-cookie", Base.get(headers, "Set-Cookie", nothing))
        if !isnothing(set_cookie_val)
            # If it's a single string, parse it
            if set_cookie_val isa AbstractString
                semi_idx = findfirst(';', set_cookie_val)
                pair_view = isnothing(semi_idx) ? SubString(set_cookie_val) : @view set_cookie_val[begin:prevind(set_cookie_val, semi_idx)]
                eq_idx = findfirst('=', pair_view)
                if !isnothing(eq_idx)
                    name = strip(@view pair_view[begin:prevind(pair_view, eq_idx)])
                    if lowercase(name) == tn_lower
                        val_view = strip(@view(pair_view[nextind(pair_view, eq_idx):end]))
                        if length(val_view) >= 2 && val_view[begin] == '"' && val_view[end] == '"'
                            return @view val_view[nextind(val_view, begin):prevind(val_view, end)]
                        end
                        return val_view
                    end
                end
            end
        end
    else
        # Iterate through headers (Vector{Pair} or HTTP.Headers)
        for (k, v) in headers
            kl = lowercase(k)
            if kl == "cookie"
                res = _extract_value_from_header(v, target_name)
                !isnothing(res) && return res
            elseif kl == "set-cookie"
                semi_idx = findfirst(';', v)
                pair_view = isnothing(semi_idx) ? SubString(v) : @view v[begin:prevind(v, semi_idx)]
                eq_idx = findfirst('=', pair_view)
                if !isnothing(eq_idx)
                    name = strip(@view pair_view[begin:prevind(pair_view, eq_idx)])
                    if lowercase(name) == tn_lower
                        val_view = strip(@view(pair_view[nextind(pair_view, eq_idx):end]))
                        if length(val_view) >= 2 && val_view[begin] == '"' && val_view[end] == '"'
                            return @view val_view[nextind(val_view, begin):prevind(val_view, end)]
                        end
                        return val_view
                    end
                end
            end
        end
    end
    return nothing
end

"""
Get a cookie value by name from a Request or Response.
Supports default values, type parsing, and decryption.
"""
function get_cookie(
    source::Any, 
    name::Union{String, Symbol},
    default::Any = nothing; 
    encrypted::Bool = false, 
    secret_key::Union{String, Nothing} = nothing,
    max_cookie_size::Union{Int, Nothing} = nothing,
    kwargs...
)
    # Use the positional default unless it's nothing and we have a keyword default
    final_default = haskey(kwargs, :default) ? kwargs[:default] : default

    if isnothing(source)
        return final_default
    end

    target_name = string(name)
    headers = if source isa HTTP.Request || source isa HTTP.Response
        source.headers
    else
        source
    end
    
    found_value = _get_cookie_lazy(headers, target_name)
    
    if isnothing(found_value)
        return final_default
    end
    
    raw_value = String(found_value)

    # Check size limit
    if !isnothing(max_cookie_size) && length(raw_value) > max_cookie_size
        return final_default
    end
    
    # Decrypt if requested
    final_value = (encrypted && !isnothing(secret_key) && secret_key != "") ? decrypt_payload(secret_key, raw_value) : raw_value
    
    if isnothing(final_default) || final_default isa String
        return final_value
    end
    
    # Try to parse as the same type as default
    try
        T = typeof(final_default)
        if T == Bool
            lv = lowercase(final_value)
            if lv in ("true", "1", "yes", "on")
                return true
            elseif lv in ("false", "0", "no", "off")
                return false
            else
                return final_default
            end
        elseif T <: Number
            return parse(T, final_value)
        else
            return final_value
        end
    catch
        return final_default
    end
end

"""
Set a cookie on an HTTP response.
If secret_key is provided in the config, the value will be encrypted.
"""
function set_cookie!(
    res::HTTP.Response, 
    name::Union{String, Symbol}, 
    value::Any; 
    config::CookieConfig = CookieConfig(),
    attrs::Dict = Dict(),
    path::Nullable{String} = nothing, 
    domain::Nullable{String} = nothing, 
    expires::Union{Nullable{DateTime}, String} = nothing, 
    maxage::Union{Nullable{Int}, String} = nothing, 
    httponly::Nullable{Bool} = nothing, 
    secure::Nullable{Bool} = nothing, 
    samesite::Nullable{String} = nothing,
    encrypted::Nullable{Bool} = nothing,
    secret_key::Nullable{String} = nothing
)
    # 1. Resolve values (Explicit param > Dict > Config Default)
    merged_attrs = Dict{Symbol, Any}()
    
    # helper to set if not nothing
    function set_if_not_nothing(key::Symbol, val)
        if !isnothing(val)
            merged_attrs[key] = val
        end
    end

    # First load from attrs dict
    for (k, v) in attrs
        merged_attrs[_normalize_attribute_name(k)] = v
    end

    # Explicit params override dict
    set_if_not_nothing(:path, path)
    set_if_not_nothing(:domain, domain)
    set_if_not_nothing(:expires, expires)
    set_if_not_nothing(:maxage, maxage)
    set_if_not_nothing(:httponly, httponly)
    set_if_not_nothing(:secure, secure)
    set_if_not_nothing(:samesite, samesite)

    # 2. Normalize and apply defaults from config
    final_path = Base.get(merged_attrs, :path, isnothing(config.path) ? "/" : config.path)
    if !startswith(final_path, "/")
        final_path = "/"
    end

    final_domain = nothing
    if haskey(merged_attrs, :domain)
        final_domain = _normalize_domain(merged_attrs[:domain])
    elseif !isnothing(config.domain)
        final_domain = config.domain
    end

    final_maxage = nothing
    final_expires = nothing
    
    # Handle Max-Age and Expires
    ma_input = Base.get(merged_attrs, :maxage, config.maxage)
    if !isnothing(ma_input)
        mv, is_logout, logout_expires = _normalize_maxage(ma_input)
        if is_logout
            final_expires = logout_expires
        end
        final_maxage = mv
    end

    if isnothing(final_expires)
        ex_input = Base.get(merged_attrs, :expires, config.expires)
        if !isnothing(ex_input)
            final_expires = _normalize_expires(ex_input)
        end
    end

    final_httponly = _normalize_bool(Base.get(merged_attrs, :httponly, config.httponly), "httponly")
    final_secure = _normalize_bool(Base.get(merged_attrs, :secure, config.secure), "secure")
    
    ss_input = Base.get(merged_attrs, :samesite, config.samesite)
    final_samesite = isnothing(ss_input) ? "Lax" : _samesite_to_mode(string(ss_input))
    if isnothing(final_samesite)
        final_samesite = "Lax" # fallback
    end
    
    # 3. Handle Encryption
    final_secret = isnothing(secret_key) ? config.secret_key : secret_key
    is_encrypted = isnothing(encrypted) ? !isnothing(final_secret) : encrypted
    str_value = string(value)
    
    # If encryption is requested but key is empty, we skip encryption (empty key is falsy for security)
    final_value = (is_encrypted && !isnothing(final_secret) && final_secret != "") ? encrypt_payload(final_secret, str_value) : str_value
    
    cookie_str = format_cookie(
        string(name), 
        final_value; 
        path=final_path, 
        domain=final_domain, 
        expires=final_expires isa DateTime ? final_expires : nothing, 
        maxage=final_maxage, 
        httponly=final_httponly, 
        secure=final_secure, 
        samesite=final_samesite
    )
    
    if length(cookie_str) > 4096
        @warn "Set-Cookie header for '$name' exceeds 4096 bytes. Some browsers may reject it."
    end
    
    # CORRECT WAY: Appending to the headers vector directly
    # HTTP.setheader would replace all existing Set-Cookie headers, which is wrong for multiple cookies.
    push!(res.headers, "Set-Cookie" => cookie_str)
    return res
end

const set! = set_cookie!

"""
Load cookie settings from a dictionary into a CookieConfig object.
Performs normalization and validation.
"""
function load_cookie_settings!(defaults::Nullable{Dict} = nothing)
    if isnothing(defaults)
        return CookieConfig()
    end
    
    optimized_defaults = Dict{Symbol, Any}()
    errors = String[]

    for (k, v) in defaults
        attr_key = _normalize_attribute_name(k)
        
        try
            if attr_key == :maxage
                mv, is_logout, logout_expires = _normalize_maxage(v)
                if !is_logout
                    optimized_defaults[attr_key] = mv
                end
            elseif attr_key in (:httponly, :secure)
                optimized_defaults[attr_key] = _normalize_bool(v, string(attr_key))
            elseif attr_key == :samesite
                if v isa String
                    mode = _samesite_to_mode(v)
                    if isnothing(mode)
                        push!(errors, "Invalid SameSite mode: $v")
                    else
                        optimized_defaults[attr_key] = mode
                    end
                else
                    optimized_defaults[attr_key] = v
                end
            elseif attr_key == :path
                if !isa(v, String)
                    push!(errors, "path: expected String, got $(typeof(v))")
                elseif !startswith(v, "/")
                    push!(errors, "path: must start with '/': $v")
                else
                    optimized_defaults[attr_key] = v
                end
            elseif attr_key == :domain
                optimized_defaults[attr_key] = _normalize_domain(v)
            elseif attr_key == :expires
                optimized_defaults[attr_key] = _normalize_expires(v)
            elseif attr_key == :secret_key
                optimized_defaults[attr_key] = isnothing(v) ? nothing : string(v)
            elseif attr_key == :max_cookie_size
                optimized_defaults[attr_key] = v isa String ? parse(Int, v) : Int(v)
            else
                push!(errors, "Unknown attribute: $k")
            end
        catch e
            push!(errors, e isa ArgumentError ? e.msg : string(e))
        end
    end
    
    if !isempty(errors)
        throw(ArgumentError(join(errors, "\n")))
    end
    
    return CookieConfig(; optimized_defaults...)
end

"""
Add a session to a MemoryStore with a time-to-live (TTL).
"""
function storesession!(store::MemoryStore{K, V}, key::K, value::V; ttl::Int = 3600) where {K, V}
    lock(store.lock) do
        store.data[key] = SessionPayload(value, Dates.now(Dates.UTC) + Dates.Second(ttl))
    end
end

"""
Remove expired sessions from a MemoryStore.
"""
function prunesessions!(store::MemoryStore)
    current_time = Dates.now(Dates.UTC)
    lock(store.lock) do
        filter!(p -> p.second.expires > current_time, store.data)
    end
end

end
