# Cookies

Oxygen provides a robust, high-performance cookie management system with native support for encryption and declarative data fetching via Extractors.

## Basic Usage

### Setting Cookies
You can set cookies on any `Response` object using the `set_cookie!` function.

```julia
using Oxygen
using HTTP

@get "/login" function(res::Response)
    # Set a simple cookie
    set_cookie!(res, "session_id", "abc-123")
    return "Logged in!"
end
```

By default, Oxygen sets `HttpOnly=true`, `Secure=true`, and `SameSite=Lax` for better security.

### Getting Cookies
There are two ways to retrieve cookies: using the `get_cookie` helper or the `Cookie` extractor.

#### 1. Using the `get_cookie` helper
```julia
@get "/profile" function(req::Request)
    user_id = get_cookie(req, "user_id", "guest")
    return "Welcome back, $user_id"
end
```

#### 2. Using the `Cookie` extractor (Recommended)
Extractors allow you to declaratively fetch and convert cookie values.

```julia
@get "/dashboard" function(user_id::Cookie{Int})
    if isnothing(user_id.value)
        return "Please log in"
    end
    return "User ID: $(user_id.value)"
end
```

## Cookie Configuration

You can configure global cookie defaults using the `configcookies` function. It supports both a `Dict` or keyword arguments.

```julia
# Set a global secret key for encryption and change default SameSite policy
configcookies(
    secret_key = "your-32-character-secret-key-here",
    samesite = "Strict",
    maxage = 3600 # 1 hour
)
```

## Encrypted Cookies

If a `secret_key` is configured, Oxygen can automatically encrypt and decrypt your cookies using AES-256-GCM.

```julia
@get "/secret" function(res::Response)
    # This value will be encrypted before being sent to the browser
    set_cookie!(res, "secret_data", "top-secret-info", encrypted=true)
    return "Secret stored!"
end

@get "/reveal" function(data::Cookie{String})
    # If the global secret_key is set, extraction automatically decrypts the value
    return "The secret is: $(data.value)"
end
```

## Advanced Options

`set_cookie!` supports all standard RFC 6265 attributes:

- `path`: The path that must exist in the requested URL (default: `/`)
- `domain`: The domain for which the cookie is valid
- `expires`: A `DateTime` or String indicating when the cookie expires
- `maxage`: Number of seconds until the cookie expires
- `httponly`: Prevents JavaScript access (default: `true`)
- `secure`: Ensures cookie is only sent over HTTPS (default: `true`)
- `samesite`: Control cross-site request behavior (`Lax`, `Strict`, or `None`)

```julia
set_cookie!(res, "theme", "dark", 
    path="/settings", 
    maxage=86400, 
    samesite="Strict"
)
```
