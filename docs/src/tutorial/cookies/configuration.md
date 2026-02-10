# Cookie Configuration

Oxygen allows you to define application-wide defaults for your cookies using the `configcookies()` function. This ensures consistency and security across your application without repeating code in every route.

## Global Configuration

You should configure your cookies at the start of your application, before calling `serve()`.

```julia
using Oxygen

# Configure defaults for ALL cookies
configcookies(
    secret_key = "my-super-secret-key-1234567890", # Required for encryption
    httponly   = true,      # Default: true (Safety first)
    samesite   = "Lax",     # Default: "Lax"
    secure     = true,      # Default: true (HTTPS only)
    maxage     = 3600       # Default: 1 hour
)
```

### Configuration Options

| Option | Description | Recommended |
|---|---|---|
| `secret_key` | Key used for AES-256 encryption. Must be kept secret. | **Required** for encryption |
| `httponly` | If `true`, JavaScript cannot access the cookie. | `true` |
| `secure` | If `true`, cookie is sent only over HTTPS. | `true` (in Prod) |
| `samesite` | Controls cross-site behavior (`"Lax"`, `"Strict"`, `"None"`). | `"Lax"` or `"Strict"` |
| `domain` | The domain the cookie is valid for. | `nothing` |
| `path` | The path the cookie is valid for. | `"/"` |

## Overriding Defaults

You can override global defaults for specific cookies by passing keyword arguments to `set_cookie!`.

```julia
# Global default is HttpOnly=true
configcookies(httponly=true)

@get "/ui-settings" function(req)
    res = Response("Settings")
    
    # Override: Allow JS to read this specific cookie
    set_cookie!(res, "language", "pt-BR", httponly=false)
    
    return res
end
```

## Common Recipes

### 1. Cross-Domain (SPA) Support

If your frontend (React/Vue) is on a different domain than your Oxygen API (e.g., API on `localhost:8080`, Frontend on `localhost:3000`), you need specific settings to allow the browser to send cookies.

```julia
configcookies(
    samesite = "None", # Required for Cross-Origin
    secure   = true    # Required if SameSite=None
)
```

> **Note:** Browsers enforce `Secure=true` if `SameSite="None"`. Oxygen will automatically upgrade the cookie to Secure if you forget this, but it's best to be explicit.

### 2. Long-Lived "Remember Me"

Sometimes you want a session to last weeks, not hours.

```julia
# 30 Days in seconds
const MONTH = 60 * 60 * 24 * 30

set_cookie!(res, "remember_token", token, maxage=MONTH)
```