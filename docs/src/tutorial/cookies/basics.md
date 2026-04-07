# Working with Cookies

Cookies are fundamental for maintaining state in web applications. Oxygen provides a secure and flexible interface for handling them, including automatic encryption, configuration defaults, and protection against common attacks (XSS/CSRF).

## Quick Start

```julia
using Oxygen
using Base64
using HTTP

# 1. Set a cookie
@get "/login" function(req)
    res = Response("Logged in")
    # Sets an encrypted cookie by default if secret_key is configured
    set_cookie!(res, "session_user", "alice", maxage=3600)
    return res
end

# 2. Read a cookie
@get "/dashboard" function(req)
    # Reads and automatically decrypts the cookie
    user = get_cookie(req, "session_user")
    return "Hello, $user"
end

serve()
```

## Basic Usage

### Setting Cookies

To set a cookie, use the `set_cookie!` function on an `HTTP.Response` object.

```julia
set_cookie!(response, name, value; kwargs...)
```

| Argument | Description | Default |
|---|---|---|
| `response` | The `HTTP.Response` object to modify | Required |
| `name` | Name of the cookie (String) | Required |
| `value` | Value to store (String, Int, Bool) | Required |
| `maxage` | Lifetime in seconds | `nothing` (Session) |
| `httponly` | Prevent JavaScript access | `true` |
| `encrypted` | Encrypt the value | `false` (unless configured) |

**Example:**
```julia
res = Response("Cookie set")

# Simple value
set_cookie!(res, "theme", "dark", httponly=false)

# Encrypted sensitive data
set_cookie!(res, "auth", "secret-token", encrypted=true)
```

### Reading Cookies

To read a cookie, use `get_cookie` with the `HTTP.Request`.

```julia
value = get_cookie(request, name; default=nothing, encrypted=false)
```

**Examples:**
```julia
# Get raw string
theme = get_cookie(req, "theme", default="light")

# Get encrypted value (automatically decrypts)
token = get_cookie(req, "auth", encrypted=true)

# Get with type conversion
count = get_cookie(req, "counter", default=0) # returns Int
```

### Removing Cookies (Logout)

To "delete" a cookie, you set its `maxage` to `0`. This tells the browser to expire it immediately.

```julia
@post "/logout" function(req)
    res = Response("Logged out")
    
    # Overwrite the cookie with empty data and immediate expiration
    set_cookie!(res, "auth", "", maxage=0)
    
    return res
end
```