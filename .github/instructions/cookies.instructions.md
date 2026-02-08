# Implementation Plan: Secure Cookie System & Extractor

## 1. Objective
Implement a robust, high-performance cookie management system for Oxygen.jl that supports native encryption, RFC 6265bis compliance, and a declarative API via Extractors. This will bridge the security gap for Single Page Applications (SPAs).

## 2. Core Components

### A. Integrated Cookie Module (`src/cookies.jl`)
Consolidate all cookie logic into a single module for high cohesion.
* **Performance:** Use `eachsplit` and `SubString` views to ensure zero-allocation lookups.
* **Robustness:** Implement strict normalization for `SameSite` (Lax/Strict/None), `HttpOnly`, `Secure`, `Expires`, and `Max-Age` (Genie-style).
* **RFC 6265 Compliance:** 
    * Support multiple `Set-Cookie` headers by `push!`-ing to the headers vector directly instead of using `HTTP.setheader`.
    * Enforce `Secure=true` when `SameSite=None`.
    * Manually append ` GMT` to `Expires` attributes formatted via `RFC1123Format` to ensure browser compatibility.
* **Encryption Hooks:** Define placeholder functions `encrypt_payload` and `decrypt_payload` to be extended by package extensions.

### B. Configuration (`src/types.jl`)
Extend the `Service` struct to include a `CookieConfig` object.
* Fields: `secret_key::Nullable{String}`, `httponly::Bool`, `secure::Bool`, `samesite::String`, `path::Nullable{String}`, `domain::Nullable{String}`.
* This allows the `serve()` function to initialize security settings globally.

### C. Cookie Extractor (`src/extractors.jl`)
Implement the `Cookie{T}` type to allow declarative data fetching in route handlers.
* **Logic:** The `extract` function uses `Cookies.get_cookie` to handle name lookup, decryption (if extension present), and type extraction.
    ```julia
    @get "/profile" function(auth::Cookie{UserSession})
        return json(auth.value)
    end
    ```

### D. Public API (`src/cookies.jl` & `src/methods.jl`)
Provide `get_cookie` and `set_cookie!` as primary entry points.
* **Flexible Input:** `get_cookie` accepts `HTTP.Request`, `HTTP.Response`, or `Dict` (for compatibility with Extractors).
* **Type Flexibility:** `set_cookie!` in `methods.jl` accepts `Any` for the value, allowing `Int`, `Float`, strings, etc.
* **Defaults:** Automatically pull default flags from `CookieConfig` to ensure "Secure by Default" behavior.

## 3. Testing Strategy
Ensure the system remains robust across different environment states.
* **Without Extension:** Verify cookies work as plain-text when `OxygenCryptoExt` is not loaded.
* **With Extension:** Verify automatic encryption/decryption when `OpenSSL` and `SHA` are present.
* **Edge Cases & Robustness:**
    * **Parsing:** Multi-quoted values, case-insensitive headers, cookies at end-of-header, and cookies without `=` (name-only).
    * **Type Safety:** Verify `get` returns defaults on parse errors (e.g. string to int) and handles various `Bool` formats ("1", "yes", "true").
    * **Normalization:** Verify underscore attributes (`max_age`, `http_only`, `same_site`) map correctly to standard attributes.
    * **SPA Patterns:** Verify `Max-Age=0` correctly triggers standard logout patterns (Expires in 1970).
    * **Configuration:** Verify cumulative error collection when loading multiple invalid settings.
    * **State Persistence:** Verify multi-cookie round-trips (Server Set -> Client Send -> Server Get).

## 4. Extension Architecture (`ext/OxygenCryptoExt.jl`)
Move heavy cryptographic dependencies (e.g., AES) to a package extension.
* **Cryptography:** Use AES-256-GCM (Galois/Counter Mode) for authenticated encryption.
* **Key Derivation:** Derive a 256-bit key from the user secret using SHA-256.
* **IV Generation:** Use OpenSSL's `RAND_bytes` for cryptographically secure random Initialization Vectors (12 bytes).
* **Integrity:** Enforce mandatory tag verification (16 bytes) via `EVP_DecryptFinal_ex` to prevent bit-flipping and tampering.
* **Encoding:** Use a custom URL-safe Base64 implementation (RFC 4648) without padding to ensure header compatibility.
* **Loading:** The extension loads automatically if `OpenSSL` and `SHA` are present in the environment.

## 4. Technical Constraints
* **Philosophy:** Maintain Oxygen's "unopinionated" and "lightweight" nature. Encryption must be optional.
* **Memory Safety:** Ensure contexts are cleaned up via finalizers or explicit cleanup blocks.
* **Multi-threading:** All cryptographic operations must be thread-safe (stateless) to support `serveparallel`.

## 6. Status
1.  [x] Define `Cookie` struct and `CookieConfig` in `src/types.jl`.
2.  [x] Create consolidated `src/cookies.jl` with optimized parsing and formatting.
3.  [x] Implement AES-256-GCM extension in `ext/OxygenCryptoExt.jl`.
4.  [x] Register `Cookie` strategy in `src/core.jl` and export `Cookies` module.
5.  [x] Implement robust normalization (SameSite, Max-Age, Booleans) in engine.
6.  [x] Implement `get_cookie` with type-safe parsing and `kwargs...` support for extractors.
7.  [x] Refactor `Cookie` extractor to use centralized logic.
8.  [x] Fix `MethodError` and `get` ambiguity in consolidated module.
9.  [x] Finalize comprehensive test suite (Testing both with/without `OxygenCryptoExt`).
10. [x] Refactor public API to use `Any` values and support multiple `Set-Cookie` headers.
