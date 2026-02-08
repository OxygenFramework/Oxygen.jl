module CookieDemo

using Oxygen
using HTTP

# 1. Basic Cookie Setting
@get "/set" function(res::Response)
    # This uses the global config (Secure=true, HttpOnly=true, SameSite=Lax by default)
    set_cookie!(res, "user_id", "12345")
    return "Cookie 'user_id' set!"
end

# 2. Declarative Cookie Extraction
# If the cookie 'user_id' exists, it will be automatically extracted and converted to Int
@get "/get" function(user_id::Cookie{Int})
    if isnothing(user_id.value)
        return "No user_id cookie found"
    else
        return "User ID is: $(user_id.value)"
    end
end

# 3. Encrypted Cookies
# To use encryption, you must set a secret key in the global config
# This can be done via 'configcookies'
# Note: Encryption requires the OxygenCryptoExt (OpenSSL & SHA)
# configcookies(Dict("secret_key" => "my-super-secret-key-1234567890"))

@get "/set_secure" function(res::Response)
    # You can force encryption for a specific cookie even if the global key isn't set 
    # (provided you pass the key explicitly)
    set_cookie!(res, "secret_data", "shhh!", encrypted=true, secret_key="my-secret")
    return "Secure cookie set!"
end

@get "/get_secure" function(req::Request)
    # Using the low-level API
    val = Cookies.get_cookie(req, "secret_data", encrypted=true, secret_key="my-secret")
    return "Decrypted data: $val"
end

# 4. Cookie Names different from parameter names
@get "/profile" function(session::Cookie{String} = Cookie("my_session", String))
    return "Session: $(session.value)"
end

# 5. Logout / Deleting Cookies
@get "/logout" function(res::Response)
    # Setting max_age to 0 effectively deletes the cookie
    set_cookie!(res, "user_id", "", maxage=0)
    return "Logged out!"
end

# Start the server
serve()

end
