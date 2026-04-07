# Cookie Security

Security is paramount when handling user state. Oxygen's cookie module is designed to be "secure by default" but gives you the tools to harden your application further.

## Automatic Encryption

Unlike standard cookies which are plain text, Oxygen supports **AES-256 GCM encryption** out of the box. This prevents users from reading or tampering with the cookie contents.

### How to Enable
1. Set a `secret_key` in `configcookies()`.
2. Use `encrypted=true` when setting/getting.

```julia
# 1. Setup
configcookies(secret_key="k3y-must-be-32-bytes-long-!!!!!!!!")

# 2. Set (Encrypted)
set_cookie!(res, "session", "user_id=42", encrypted=true)
# Browser sees: "session=8a7s6d87a6sd876a..."

# 3. Get (Decrypted)
val = get_cookie(req, "session", encrypted=true)
# Server sees: "user_id=42"
```

> **Warning:** If you change your `secret_key`, all existing encrypted cookies will become unreadable (invalid).

## The Security Checklist

Every cookie you set for authentication should follow these rules:

| Attribute | Why? | How? |
|---|---|---|
| **HttpOnly** | Prevents XSS (JavaScript cannot steal the token). | `httponly=true` |
| **Secure** | Prevents network sniffing (HTTPS only). | `secure=true` |
| **SameSite** | Prevents CSRF attacks. | `samesite="Strict"` or `"Lax"` |
| **Encrypted** | Prevents tampering and information leakage. | `encrypted=true` |

### Example: The Perfect Auth Cookie

```julia
set_cookie!(res, "auth_token", token,
    httponly = true,    # No JS access
    secure   = true,    # HTTPS only
    samesite = "Strict",# No cross-site usage
    encrypted= true,    # Tamper-proof
    maxage   = 3600     # Expires in 1 hour
)
```

## Advanced: SameSite Policy

* **`Strict`**: The cookie is sent ONLY for first-party requests. Best for critical actions (like changing passwords).
* **`Lax`** (Default): Sent on navigation (clicking a link) but not on embedded requests (images/frames). Good balance for most apps.
* **`None`**: Sent on all requests. Requires `Secure=true`. Use this for APIs serving 3rd party SPAs.

```julia
# For an API serving a separate Frontend domain:
set_cookie!(res, "session", id, samesite="None", secure=true)
```