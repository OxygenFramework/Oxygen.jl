module CookieUtil

using HTTP
using Dates
using ..Types
using ..Cookies

export set_cookie!

"""
Set a cookie on an HTTP response.
If secret_key is provided in the config, the value will be encrypted.
"""
function set_cookie!(
    res::HTTP.Response, 
    name::String, 
    value::String; 
    config::CookieConfig = CookieConfig(),
    path::String = "/", 
    domain::Nullable{String} = nothing, 
    expires::Nullable{DateTime} = nothing, 
    maxage::Nullable{Int} = nothing, 
    httponly::Nullable{Bool} = nothing, 
    secure::Nullable{Bool} = nothing, 
    samesite::Nullable{String} = nothing
)
    # Use config defaults if not explicitly provided
    h_only = isnothing(httponly) ? config.httponly : httponly
    sec = isnothing(secure) ? config.secure : secure
    ss = isnothing(samesite) ? config.samesite : samesite
    
    # Encrypt value if secret_key is present
    final_value = !isnothing(config.secret_key) ? encrypt_payload(config.secret_key, value) : value
    
    cookie_str = format_cookie(
        name, 
        final_value; 
        path=path, 
        domain=domain, 
        expires=expires, 
        maxage=maxage, 
        httponly=h_only, 
        secure=sec, 
        samesite=ss
    )
    
    HTTP.setheader(res, "Set-Cookie" => cookie_str)
    return res
end

end
