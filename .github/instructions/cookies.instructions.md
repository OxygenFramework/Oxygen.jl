# Implementation Plan: Secure Cookie System & Extractor

## 1. Objective
Implement a robust, high-performance cookie management system for Oxygen.jl that supports native encryption, RFC 6265bis compliance, and a declarative API via Extractors. This will bridge the security gap for Single Page Applications (SPAs).

## 2. Core Components

### A. Security Module (`src/security/Cookies.jl`)
Create a dedicated internal module to handle low-level parsing and formatting.
* **Performance:** Use `eachsplit` and `SubString` views to ensure zero-allocation lookups.
* **Validation:** Implement strict validation for `SameSite` (Lax/Strict/None), `HttpOnly`, and `Secure` flags.
* **Encryption Hooks:** Define placeholder functions `encrypt_payload` and `decrypt_payload` to be extended by package extensions.

### B. Configuration (`src/types.jl`)
Extend the `Service` struct to include a `CookieConfig` object.
* Fields: `secret_key::Nullable{String}`, `httponly::Bool`, `secure::Bool`, `samesite::String`.
* This allows the `serve()` function to initialize security settings globally.

### C. Cookie Extractor (`src/extractors.jl`)
Implement the `Cookie{T}` type to allow declarative data fetching in route handlers.
* **Logic:** The `extract` function will look up the cookie by name, verify the signature/encryption (if a secret is provided), and parse the value into type `T`.
* **Usage Example:** ```julia
    @get "/profile" function(auth::Cookie{UserSession})
        return json(auth.value)
    end
    ```

### D. Response Utility (`src/utilities/cookies.jl`)
Add a `set_cookie!` utility that modifies an `HTTP.Response`.
* It should automatically pull default security flags from the `CONTEXT[]` to ensure "Secure by Default" behavior.

## 3. Extension Architecture (`ext/OxygenCryptoExt.jl`)
Move heavy cryptographic dependencies (e.g., AES) to a package extension.
* The extension will only load if the user explicitly installs a supported crypto library.
* It will overwrite the placeholder `encrypt_payload` and `decrypt_payload` functions from the core.

## 4. Technical Constraints
* **Philosophy:** Maintain Oxygen's "unopinionated" and "lightweight" nature. Encryption must be optional.
* **Revise Compatibility:** Ensure the new structures work with the existing `ReviseHandler`.
* **Multi-threading:** All cookie parsing must be thread-safe to support `serveparallel`.

## 5. Next Steps
1.  Define the `Cookie` struct in `src/types.jl`.
2.  Port the optimized `nullablevalue` logic to `src/security/Cookies.jl`.
3.  Register the new `Cookie` strategy in `create_param_parser` inside `src/core.jl`.