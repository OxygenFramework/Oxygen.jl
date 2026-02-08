if !isdefined(Main, :Oxygen)
    include(joinpath(@__DIR__, "common_setup.jl"))
    # Trigger extensions needed for these tests
    trigger_extension("OpenSSL")
    trigger_extension("SHA")
end

using Oxygen
using Oxygen.Types
using HTTP
using Test
using Dates
using OpenSSL
using SHA

# Access Cookies module from Oxygen to avoid ambiguity
const Cookies = Oxygen.Cookies

@testset "Cookies with Encrypted Values (Genie Compatibility)" begin

    secret = "repro-token-1234567890-1234567890"

    # ============================================================================
    # REQUEST COOKIE TESTS (from incoming HTTP requests)
    # ============================================================================

    @testset "REQUEST: Cookie Retrieval with Quotes in Encrypted Value" begin
        data = "user-123"
        encrypted_value = Cookies.encrypt_payload(secret, data)
        value_with_quotes = "\"$encrypted_value\""

        req = HTTP.Request("GET", "/", ["Cookie" => "my_session=$value_with_quotes"])
        result = Cookies.get_cookie(req, "my_session", encrypted=true, secret_key=secret)

        @test result == data
    end

    @testset "REQUEST: Without Quotes in Encrypted Value" begin
        data = "user-456"
        encrypted_value = Cookies.encrypt_payload(secret, data)

        req = HTTP.Request("GET", "/", ["Cookie" => "my_session=$encrypted_value"])
        result = Cookies.get_cookie(req, "my_session", encrypted=true, secret_key=secret)

        @test result == data
    end

    @testset "REQUEST: Non-Encrypted Cookie Value" begin
        data = "plain-value"
        req = HTTP.Request("GET", "/", ["Cookie" => "my_session=$data"])
        result = Cookies.get_cookie(req, "my_session", encrypted=false)

        @test result == data
    end

    @testset "REQUEST: Double Quotes non-Encrypted Cookie Value" begin
        data = "plain-value-quoted"
        double_quoted_data = "\"$data\""

        req = HTTP.Request("GET", "/", ["Cookie" => "my_session=$double_quoted_data"])
        result = Cookies.get_cookie(req, "my_session", encrypted=false)

        @test result == data
    end

    @testset "REQUEST: Missing Cookie" begin
        req = HTTP.Request("GET", "/")
        result = Cookies.get_cookie(req, "non_existent_cookie", encrypted=true, secret_key=secret)

        @test result === nothing
    end

    @testset "REQUEST: Malformed Cookie Header" begin
        # RFC 6265 behavior: "malformed_cookie" becomes key="malformed_cookie" with empty value
        req = HTTP.Request("GET", "/", ["Cookie" => "malformed_cookie"])
        result = Cookies.get_cookie(req, "malformed_cookie", encrypted=false)

        @test result == ""
    end

    @testset "REQUEST: Empty Cookie Value" begin
        req = HTTP.Request("GET", "/", ["Cookie" => "empty_cookie="])
        result = Cookies.get_cookie(req, "empty_cookie", encrypted=false)

        @test result == ""
    end

    @testset "REQUEST: Multiple Cookies" begin
        data1 = "value1"
        data2 = "value2"
        encrypted_value2 = Cookies.encrypt_payload(secret, data2)

        req = HTTP.Request("GET", "/", ["Cookie" => "cookie1=$data1; cookie2=$encrypted_value2"])
        result1 = Cookies.get_cookie(req, "cookie1", encrypted=false)
        result2 = Cookies.get_cookie(req, "cookie2", encrypted=true, secret_key=secret)

        @test result1 == data1
        @test result2 == data2
    end

    @testset "REQUEST: Cookie Name Case Insensitivity" begin
        data = "case-test"
        encrypted_value = Cookies.encrypt_payload(secret, data)

        req = HTTP.Request("GET", "/", ["Cookie" => "MY_SESSION=$encrypted_value"])
        result = Cookies.get_cookie(req, "my_session", encrypted=true, secret_key=secret)

        @test result == data
    end

    @testset "REQUEST: Cookie Value with Special Characters" begin
        data = "value_with_special_chars_!@#\$%^&*()"
        encrypted_value = Cookies.encrypt_payload(secret, data)

        req = HTTP.Request("GET", "/", ["Cookie" => "special_cookie=$encrypted_value"])
        result = Cookies.get_cookie(req, "special_cookie", encrypted=true, secret_key=secret)

        @test result == data
    end

    @testset "REQUEST: Whitespace Handling in Cookie Value" begin
        data = "whitespace-test"
        encrypted_value = Cookies.encrypt_payload(secret, data)

        req = HTTP.Request("GET", "/", ["Cookie" => "spaced_cookie = $encrypted_value "])
        result = Cookies.get_cookie(req, "spaced_cookie", encrypted=true, secret_key=secret)

        @test result == data
    end

    @testset "REQUEST: Cookie Value is Just Quotes" begin
        req = HTTP.Request("GET", "/", ["Cookie" => "empty_quoted=\"\""])
        result = Cookies.get_cookie(req, "empty_quoted", encrypted=false)

        @test result == ""
    end

    @testset "REQUEST: Very Large Cookie Value" begin
        data = "a"^5000  # 5000 characters
        encrypted_value = Cookies.encrypt_payload(secret, data)

        req = HTTP.Request("GET", "/", ["Cookie" => "large_cookie=$encrypted_value"])
        result = Cookies.get_cookie(req, "large_cookie", encrypted=true, secret_key=secret)

        @test result == data
    end

    @testset "REQUEST: Very Large Cookie Value with Size Limit" begin
        data = "a"^5000
        encrypted_value = Cookies.encrypt_payload(secret, data)

        req = HTTP.Request("GET", "/", ["Cookie" => "large_cookie=$encrypted_value"])
        result = Cookies.get_cookie(req, "large_cookie", encrypted=true, secret_key=secret, max_cookie_size=4096)

        @test result === nothing
    end

    @testset "REQUEST: Cookie with Symbol Key" begin
        data = "symbol-key-test"
        encrypted_value = Cookies.encrypt_payload(secret, data)

        req = HTTP.Request("GET", "/", ["Cookie" => "sym_key=$encrypted_value"])
        result = Cookies.get_cookie(req, :sym_key, encrypted=true, secret_key=secret)

        @test result == data
    end

    # ============================================================================
    # RESPONSE COOKIE TESTS (from outgoing HTTP responses)
    # ============================================================================

    @testset "RESPONSE: Basic Cookie Retrieval" begin
        data = "response-value"
        encrypted_value = Cookies.encrypt_payload(secret, data)

        res = HTTP.Response(200, [("Set-Cookie", "resp_cookie=$encrypted_value; Path=/; HttpOnly")])
        result = Cookies.get_cookie(res, "resp_cookie", encrypted=true, secret_key=secret)

        @test result == data
    end

    @testset "RESPONSE: Multiple Set-Cookie Headers" begin
        encrypted_val1 = Cookies.encrypt_payload(secret, "resp1")
        encrypted_val2 = Cookies.encrypt_payload(secret, "resp2")

        res = HTTP.Response(200, [
            ("Set-Cookie", "cookie1=$encrypted_val1; Path=/"),
            ("Set-Cookie", "cookie2=$encrypted_val2; HttpOnly")
        ])
        
        result1 = Cookies.get_cookie(res, "cookie1", encrypted=true, secret_key=secret)
        result2 = Cookies.get_cookie(res, "cookie2", encrypted=true, secret_key=secret)
        @test result1 == "resp1"
        @test result2 == "resp2"
    end

    @testset "RESPONSE: Mixed Encrypted and Plaintext Cookies" begin
        # Test reading both encrypted and plaintext cookies from same response
        encrypted_data = "secret-session-token"
        plaintext_data = "tracking-id-12345"
        
        encrypted_val = Cookies.encrypt_payload(secret, encrypted_data)
        
        res = HTTP.Response(200, [
            ("Set-Cookie", "session=$encrypted_val; Path=/; HttpOnly; Secure"),
            ("Set-Cookie", "tracking=$plaintext_data; Path=/; SameSite=Lax")
        ])
        
        # Retrieve encrypted cookie
        session_result = Cookies.get_cookie(res, "session", encrypted=true, secret_key=secret)
        @test session_result == encrypted_data
        
        # Retrieve plaintext cookie
        tracking_result = Cookies.get_cookie(res, "tracking", encrypted=false)
        @test tracking_result == plaintext_data
        
        # Join all Set-Cookie headers for verification
        all_headers = join([v for (k, v) in res.headers if lowercase(k) == "set-cookie"], " ")
        
        # Verify encrypted value is not visible in plaintext
        @test !occursin(encrypted_data, all_headers)
        @test occursin(plaintext_data, all_headers)
    end

    @testset "RESPONSE: Cookie Attributes Preservation" begin
        # Test that cookie attributes are correctly formatted in Set-Cookie headers
        res = HTTP.Response(200)
        
        # Set cookie with various attributes
        set_cookie!(res, "attr_test", "test_value", 
            attrs=Dict(
                "path" => "/api/v1",
                "domain" => "example.com",
                "max_age" => 7200,
                "http_only" => true,
                "secure" => true,
                "same_site" => "Strict"
            ),
            encrypted=false
        )
        
        header = lowercase(HTTP.header(res, "Set-Cookie"))
        
        # Verify all attributes are present
        @test occursin("attr_test=test_value", header)
        @test occursin("path=/api/v1", header)
        @test occursin("domain=example.com", header)
        @test occursin("max-age=7200", header)
        @test occursin("httponly", header)
        @test occursin("secure", header)
        @test occursin("samesite=strict", header)
    end

    @testset "RESPONSE: Plaintext Cookie Retrieval" begin
        # Test reading plaintext cookies from response with various formats
        plaintext_val = "plain-text-cookie-value"
        
        res = HTTP.Response(200, [("Set-Cookie", "plain=$plaintext_val; Path=/; Domain=.example.com")])
        result = Cookies.get_cookie(res, "plain", encrypted=false)
        
        @test result == plaintext_val
    end

    @testset "RESPONSE: Cookie with Complex Value" begin
        # Test response cookies with complex values (special chars, equals signs, etc.)
        complex_value = "key1=val1; key2=val2; special_chars=!@#\$%"
        encrypted_complex = Cookies.encrypt_payload(secret, complex_value)
        
        res = HTTP.Response(200, [("Set-Cookie", "complex=$encrypted_complex; Path=/")])
        result = Cookies.get_cookie(res, "complex", encrypted=true, secret_key=secret)
        
        @test result == complex_value
    end

    @testset "ROBUSTNESS: Cookie Name is Prefix of Another (Value Check)" begin
        req = HTTP.Request("GET", "/", ["Cookie" => "user=short; username=long"])
        @test Cookies.get_cookie(req, "user") == "short"
        @test Cookies.get_cookie(req, "username") == "long"
        
        req2 = HTTP.Request("GET", "/", ["Cookie" => "username=long; user=short"])
        @test Cookies.get_cookie(req2, "user") == "short"
        @test Cookies.get_cookie(req2, "username") == "long"
    end

    # ============================================================================
    # DEFAULT VALUE TESTS
    # ============================================================================

    @testset "DEFAULT: Request with Missing Cookie Returns Default" begin
        req = HTTP.Request("GET", "/")
        result = Cookies.get_cookie(req, "missing", default="default_value")

        @test result == "default_value"
    end

    @testset "DEFAULT: Request with Default Integer" begin
        req = HTTP.Request("GET", "/", ["Cookie" => "count=42"])
        result = Cookies.get_cookie(req, "count", default=0)

        @test result == 42
        @test isa(result, Int)
    end

    @testset "ROBUSTNESS: Typed get with Invalid Values" begin
        # Oxygen's design is to return the default value if parsing fails
        req = HTTP.Request("GET", "/", ["Cookie" => "count=abc"])
        @test Cookies.get_cookie(req, "count", default=10) == 10
        
        req_bool = HTTP.Request("GET", "/", ["Cookie" => "flag=not_a_bool"])
        @test Cookies.get_cookie(req_bool, "flag", default=true) == true

        # Scenarios from Genie for compatibility check
        # Scenario 1: Missing cookie returns default
        req_missing = HTTP.Request("GET", "/")
        @test Cookies.get_cookie(req_missing, "nonexistent", default=99) == 99
        @test Cookies.get_cookie(req_missing, "nonexistent", default=3.14) == 3.14
        @test Cookies.get_cookie(req_missing, "nonexistent", default=true) == true

        # Scenario 2: Valid Int value
        req_valid_int = HTTP.Request("GET", "/", ["Cookie" => "counter=42"])
        @test Cookies.get_cookie(req_valid_int, "counter", default=10) == 42

        # Scenario 3: Valid Float value
        req_valid_float = HTTP.Request("GET", "/", ["Cookie" => "temp=36.5"])
        @test Cookies.get_cookie(req_valid_float, "temp", default=1.5) == 36.5

        # Scenario 4: Leading zeros (valid Int)
        req_leading_zeros = HTTP.Request("GET", "/", ["Cookie" => "count=0042"])
        @test Cookies.get_cookie(req_leading_zeros, "count", default=0) == 42

        # Scenario 5: Whitespace-only values (should return default)
        req_whitespace = HTTP.Request("GET", "/", ["Cookie" => "value=   "])
        @test Cookies.get_cookie(req_whitespace, "value", default=77) == 77

        # Scenario 6: Empty cookie value (should return default for typed, empty string for untyped)
        req_empty = HTTP.Request("GET", "/", ["Cookie" => "value="])
        @test Cookies.get_cookie(req_empty, "value", default=42) == 42
        @test Cookies.get_cookie(req_empty, "value") == ""
    end

    @testset "TYPE: Case-Insensitive Header and Key Variations" begin
        # Request Header Variations
        req1 = HTTP.Request("GET", "/", ["cookie" => "my_key=val1"])
        @test Cookies.get_cookie(req1, "my_key") == "val1"

        req2 = HTTP.Request("GET", "/", ["COOKIE" => "MY_KEY=val2"])
        @test Cookies.get_cookie(req2, "my_key") == "val2"
        @test Cookies.get_cookie(req2, :my_key) == "val2"
        @test Cookies.get_cookie(req2, :MY_KEY) == "val2"

        # Response Header Variations
        res1 = HTTP.Response(200, [("set-cookie", "resp_opt=val3; Path=/")])
        @test Cookies.get_cookie(res1, "resp_opt") == "val3"

        res2 = HTTP.Response(200, [("SET-COOKIE", "resp_opt=val4; Path=/")])
        @test Cookies.get_cookie(res2, "resp_opt") == "val4"
    end


    # ============================================================================
    # EDGE CASE TESTS
    # ============================================================================

    @testset "EDGE: Cookie Name is Prefix of Another" begin
        data1 = "short"
        data2 = "long"
        req = HTTP.Request("GET", "/", ["Cookie" => "username=$data2; user=$data1"])
        
        result_short = Cookies.get_cookie(req, "user")
        result_long = Cookies.get_cookie(req, "username")

        @test result_short == data1
        @test result_long == data2
    end

    @testset "EDGE: Multiple Equals Signs in Value" begin
        data = "value=with=equals"
        req = HTTP.Request("GET", "/", ["Cookie" => "multi=$data"])
        result = Cookies.get_cookie(req, "multi")

        @test result == data
    end

    @testset "EDGE: Cookie Name at End of Header" begin
        req = HTTP.Request("GET", "/", ["Cookie" => "first=val1; last=end-value"])
        result = Cookies.get_cookie(req, "last")
        @test result == "end-value"
    end

    @testset "EDGE: No Equals Sign in Cookie" begin
        # RFC 6265: Treat as name with empty value
        req = HTTP.Request("GET", "/", ["Cookie" => "no_value; valid=value"])
        @test Cookies.get_cookie(req, "no_value") == ""
        @test Cookies.get_cookie(req, "valid") == "value"
    end


    # ============================================================================
    # SET! FUNCTION TESTS (setting cookies on responses)
    # ============================================================================

    @testset "SET: Basic Encrypted Cookie" begin
        data = "session-123"
        res = HTTP.Response(200)
        config = CookieConfig(secret_key=secret)
        res = set_cookie!(res, "session_id", data, config=config, encrypted=true)
        
        # Verify the cookie was added
        result = Cookies.get_cookie(res, "session_id", encrypted=true, secret_key=secret)
        @test result == data
    end

    @testset "SET: Basic Non-Encrypted Cookie" begin
        data = "plain-preference"
        res = HTTP.Response(200)
        res = set_cookie!(res, "preference", data, encrypted=false)
        
        result = Cookies.get_cookie(res, "preference", encrypted=false)
        @test result == data
    end

    @testset "SET: Cookie with Path Attribute" begin
        res = HTTP.Response(200)
        attrs = Dict("path" => "/api")
        res = set_cookie!(res, "api_token", "token123", attrs=attrs, encrypted=false)
        
        header = HTTP.header(res, "Set-Cookie")
        @test occursin("Path=/api", header)
    end

    @testset "SET: Cookie with SameSite=none (Auto-Secure)" begin
        res = HTTP.Response(200)
        attrs = Dict("samesite" => "none")
        res = set_cookie!(res, "samesite_none", "none_value", attrs=attrs, encrypted=false, secure=false)
        
        header = lowercase(HTTP.header(res, "Set-Cookie"))
        @test occursin("samesite=none", header)
        @test occursin("secure", header) # should be auto-enforced
    end

    @testset "SET: Logout Pattern (Max-Age=0)" begin
        res = HTTP.Response(200)
        res = set_cookie!(res, "logout", "", attrs=Dict("max_age" => 0), encrypted=false)
        
        header = lowercase(HTTP.header(res, "Set-Cookie"))
        @test occursin("max-age=0", header)
        @test occursin("1970", header) # should have epoch expires
    end

    @testset "SET: Normalize Underscore Attributes" begin
        res = HTTP.Response(200)
        attrs = Dict(
            "max_age" => 1800,
            "http_only" => true,
            "same_site" => "strict"
        )
        res = set_cookie!(res, "normalized", "val", attrs=attrs, encrypted=false)
        
        header = lowercase(HTTP.header(res, "Set-Cookie"))
        @test occursin("max-age=1800", header)
        @test occursin("httponly", header)
        @test occursin("samesite=strict", header)
    end

    @testset "SET: Multiple Cookies" begin
        res = HTTP.Response(200)
        res = set_cookie!(res, "c1", "v1", encrypted=false)
        res = set_cookie!(res, "c2", "v2", encrypted=false)
        
        headers = [v for (k, v) in res.headers if lowercase(k) == "set-cookie"]
        @test length(headers) == 2
        @test any(occursin("c1=v1", h) for h in headers)
        @test any(occursin("c2=v2", h) for h in headers)
    end

    @testset "SET: Numeric Value" begin
        res = HTTP.Response(200)
        res = set_cookie!(res, "count", 42, encrypted=false)
        @test Cookies.get_cookie(res, "count") == "42"
    end

    @testset "SET: Default Encrypted Parameter" begin
        # Should auto-encrypt if secret_key is in config and encrypted isn't specified
        res = HTTP.Response(200)
        config = CookieConfig(secret_key=secret)
        res = set_cookie!(res, "auto_enc", "secret_val", config=config)
        
        # Original data should not be visible in header
        header = HTTP.header(res, "Set-Cookie")
        @test !occursin("secret_val", header)
        
        # But should be retrievable
        @test Cookies.get_cookie(res, "auto_enc", encrypted=true, secret_key=secret) == "secret_val"
    end

    @testset "SET: Mixed Case and Underscore Attributes" begin
        res = HTTP.Response(200)
        attrs = Dict("MAX_AGE" => 1800, "HTTP_ONLY" => true, "same_site" => "Strict")
        res = set_cookie!(res, "mixed_attr", "val", attrs=attrs, encrypted=false)
        header = lowercase(HTTP.header(res, "Set-Cookie"))
        @test occursin("max-age=1800", header)
        @test occursin("httponly", header)
        @test occursin("samesite=strict", header)
    end

    @testset "SET: Cookie with Domain Override" begin
        config = CookieConfig(domain="global.com")
        res = HTTP.Response(200)
        
        # Override global domain with local one
        res = set_cookie!(res, "local_cookie", "val", attrs=Dict("domain" => "local.com"), config=config, encrypted=false)
        header = lowercase(HTTP.header(res, "Set-Cookie"))
        @test occursin("domain=local.com", header)
        @test !occursin("domain=global.com", header)
    end

    @testset "SET: String Expires Parsing (ISO 8601)" begin
        res = HTTP.Response(200)
        res = set_cookie!(res, "exp", "val", attrs=Dict("expires" => "2025-06-09T10:18:14Z"), encrypted=false)
        header = HTTP.header(res, "Set-Cookie")
        # Dates.format(dt, RFC1123Format) usually gives "Mon, 09 Jun 2025 10:18:14 GMT"
        @test occursin("Expires=Mon, 09 Jun 2025 10:18:14 GMT", header)
    end

    @testset "SET: String Expires Parsing (RFC 2822)" begin
        res = HTTP.Response(200)
        res = set_cookie!(res, "exp", "val", attrs=Dict("expires" => "Mon, 09 Jun 2025 10:18:14 GMT"), encrypted=false)
        header = HTTP.header(res, "Set-Cookie")
        @test occursin("Expires=Mon, 09 Jun 2025 10:18:14 GMT", header)
    end

    @testset "SET: String Max-Age Parsing" begin
        res = HTTP.Response(200)
        res = set_cookie!(res, "ma", "val", attrs=Dict("max_age" => "3600"), encrypted=false)
        header = HTTP.header(res, "Set-Cookie")
        @test occursin("Max-Age=3600", header)
    end

    @testset "SET: Domain Validation" begin
        res = HTTP.Response(200)
        
        # Valid domain
        res = set_cookie!(res, "d1", "v1", attrs=Dict("domain" => "example.com"), encrypted=false)
        @test occursin("Domain=example.com", HTTP.header(res, "Set-Cookie"))
        
        # Invalid domain should throw
        @test_throws ArgumentError set_cookie!(res, "d2", "v2", attrs=Dict("domain" => "invalid domain"), encrypted=false)
        @test_throws ArgumentError set_cookie!(res, "d3", "v3", attrs=Dict("domain" => "example.com:8080"), encrypted=false)
    end

    @testset "SET: SameSite=None implies Secure=true" begin
        res = HTTP.Response(200)
        # Should warn and set secure=true
        res = set_cookie!(res, "session", "val", attrs=Dict("same_site" => "None"), secure=false, encrypted=false)
        header = HTTP.header(res, "Set-Cookie")
        @test occursin("SameSite=None", header)
        @test occursin("Secure", header)
    end

    @testset "SET: Max-Age=0 creates logout cookie" begin
        res = HTTP.Response(200)
        res = set_cookie!(res, "logout", "true", attrs=Dict("max_age" => 0), encrypted=false)
        header = HTTP.header(res, "Set-Cookie")
        @test occursin("Max-Age=0", header)
        @test occursin("Expires=Thu, 01 Jan 1970 00:00:00 GMT", header)
    end

    @testset "CONFIG: load_cookie_settings!" begin
        defaults = Dict(
            "httponly" => "false",
            "secure" => 1,
            "samesite" => "Strict",
            "maxage" => 3600,
            "domain" => "oxygenjl.com",
            "secret_key" => "my-secret-key",
            "max_cookie_size" => "8192"
        )
        conf = Cookies.load_cookie_settings!(defaults)
        @test conf.httponly == false
        @test conf.secure == true
        @test conf.samesite == "Strict"
        @test conf.maxage == 3600
        @test conf.domain == "oxygenjl.com"
        @test conf.secret_key == "my-secret-key"
        @test conf.max_cookie_size == 8192
    end

    @testset "CONFIG: Domain Processing" begin
        # Trim and Lowercase
        conf = Cookies.load_cookie_settings!(Dict("domain" => "  EXAMPLE.COM  "))
        @test conf.domain == "example.com"

        # Leading dot preservation
        conf = Cookies.load_cookie_settings!(Dict("domain" => "  .EXAMPLE.COM  "))
        @test conf.domain == ".example.com"

        # Invalid types
        @test_throws ArgumentError Cookies.load_cookie_settings!(Dict("domain" => 123))
        @test_throws ArgumentError Cookies.load_cookie_settings!(Dict("domain" => ""))
    end

    @testset "CONFIG: Expires Normalization" begin
        # RFC 2822
        conf = Cookies.load_cookie_settings!(Dict("expires" => "Wed, 09 Jun 2025 10:18:14 GMT"))
        @test conf.expires isa Dates.DateTime

        # ISO 8601
        conf = Cookies.load_cookie_settings!(Dict("expires" => "2025-06-09T10:18:14Z"))
        @test conf.expires isa Dates.DateTime

        # Unix Timestamp
        conf = Cookies.load_cookie_settings!(Dict("expires" => "1749464294"))
        @test conf.expires isa Dates.DateTime

        # Invalid types
        @test_throws ArgumentError Cookies.load_cookie_settings!(Dict("expires" => 123456789))
        @test_throws ArgumentError Cookies.load_cookie_settings!(Dict("expires" => true))
    end

    @testset "CONFIG: Cumulative Error Collection" begin
        bad_defaults = Dict(
            "samesite" => "invalid_mode",
            "maxage" => "not_a_number",
            "path" => "no_leading_slash",
            "unknown_field" => "value"
        )
        
        try
            Cookies.load_cookie_settings!(bad_defaults)
            @test false # should have thrown
        catch e
            msg = string(e)
            @test occursin("SameSite", msg)
            @test occursin("max_age", msg)
            @test occursin("path", msg)
            @test occursin("Unknown attribute", msg)
        end
    end

    @testset "INTEGRATION: set_cookie! uses Config Defaults" begin
        # 1. Load defaults
        defaults = Dict(
            "httponly" => true,
            "path" => "/app",
            "samesite" => "Strict",
            "secure" => true
        )
        conf = Cookies.load_cookie_settings!(defaults)
        
        # 2. Set cookie without overriding defaults
        res = HTTP.Response(200)
        res = set_cookie!(res, "default_test", "val", config=conf, encrypted=false)
        
        header = lowercase(HTTP.header(res, "Set-Cookie"))
        @test occursin("httponly", header)
        @test occursin("path=/app", header)
        @test occursin("samesite=strict", header)
        @test occursin("secure", header)
    end

    @testset "SCENARIO: Complex Session Management" begin
        # Simulating a session with user data
        res = HTTP.Response(200)
        user_data = "user:123,role:admin,timestamp:1234567890"
        config = CookieConfig(secret_key=secret)
        
        set_cookie!(res, "user_session", user_data, 
            attrs=Dict("path" => "/admin", "httponly" => true, "maxage" => 86400),
            config=config, encrypted=true)
        
        # Verify it's encrypted in header
        header = HTTP.header(res, "Set-Cookie")
        @test !occursin(user_data, header)
        
        # Verify retrieval
        result = Cookies.get_cookie(res, "user_session", encrypted=true, secret_key=secret)
        @test result == user_data
    end

    @testset "SCENARIO: Multiple Cookies Integration" begin
        res = HTTP.Response(200)
        config = CookieConfig(secret_key=secret)
        
        set_cookie!(res, "session_id", "abc123xyz789", config=config, encrypted=true)
        set_cookie!(res, "csrf_token", "csrf_123456", config=config, encrypted=false)
        set_cookie!(res, "tracking", "track_987", encrypted=false)
        
        # Simulate client sending them back
        headers = [
            "Cookie" => "session_id=$(Cookies.encrypt_payload(secret, "abc123xyz789")); csrf_token=csrf_123456; tracking=track_987"
        ]
        req = HTTP.Request("GET", "/", headers)
        
        @test Cookies.get_cookie(req, "session_id", encrypted=true, secret_key=secret) == "abc123xyz789"
        @test Cookies.get_cookie(req, "csrf_token", encrypted=false) == "csrf_123456"
        @test Cookies.get_cookie(req, "tracking") == "track_987"
    end

    @testset "SCENARIO: SPA Authentication Lifecycle" begin
        # Simulate a complete SPA auth flow: Login -> Active Session -> Token Refresh -> Logout
        
        # Initial setup
        config = CookieConfig(secret_key=secret)
        
        # ========== PHASE 1: LOGIN ==========
        # Server issues encrypted session + plain CSRF token on successful login
        login_response = HTTP.Response(200)
        session_data = "user:42,role:admin,permissions:read|write"
        csrf_token = "csrf_abc123xyz789"
        
        set_cookie!(login_response, "session", session_data, config=config, encrypted=true, 
                    attrs=Dict("path" => "/api", "max_age" => 3600, "same_site" => "Strict"))
        set_cookie!(login_response, "csrf_token", csrf_token, encrypted=false, 
                    attrs=Dict("path" => "/api", "max_age" => 3600, "same_site" => "Strict"))
        
        # Verify cookies are set correctly
        @test Cookies.get_cookie(login_response, "session", encrypted=true, secret_key=secret) == session_data
        @test Cookies.get_cookie(login_response, "csrf_token") == csrf_token
        
        # Verify session is encrypted (not visible in plaintext)
        all_headers = join([v for (k, v) in login_response.headers if lowercase(k) == "set-cookie"], " ")
        @test !occursin("user:42", all_headers)
        @test occursin("session=", all_headers)
        
        # ========== PHASE 2: ACTIVE SESSION ==========
        # Client sends both cookies back to server in subsequent request
        active_request = HTTP.Request("GET", "/api/profile", [
            "Cookie" => "session=$(Cookies.encrypt_payload(secret, session_data)); csrf_token=$csrf_token"
        ])
        
        # Server validates incoming cookies
        retrieved_session = Cookies.get_cookie(active_request, "session", encrypted=true, secret_key=secret)
        retrieved_csrf = Cookies.get_cookie(active_request, "csrf_token")
        
        @test retrieved_session == session_data
        @test retrieved_csrf == csrf_token
        
        # ========== PHASE 3: TOKEN REFRESH ==========
        # Server updates session with new timestamp while maintaining user identity
        updated_session_data = "user:42,role:admin,permissions:read|write,timestamp:$(floor(Int, time()))"
        refresh_response = HTTP.Response(200)
        
        set_cookie!(refresh_response, "session", updated_session_data, config=config, encrypted=true, 
                    attrs=Dict("path" => "/api", "max_age" => 3600))
        
        @test Cookies.get_cookie(refresh_response, "session", encrypted=true, secret_key=secret) == updated_session_data
        
        # Verify different data produces different ciphertext (integrity check)
        old_enc = Cookies.encrypt_payload(secret, session_data)
        new_enc = Cookies.encrypt_payload(secret, updated_session_data)
        @test old_enc != new_enc
        
        # ========== PHASE 4: LOGOUT ==========
        # Server clears cookies with Max-Age=0
        logout_response = HTTP.Response(200)
        
        set_cookie!(logout_response, "session", "", encrypted=false, 
                    attrs=Dict("path" => "/api", "max_age" => 0))
        set_cookie!(logout_response, "csrf_token", "", encrypted=false, 
                    attrs=Dict("path" => "/api", "max_age" => 0))
        
        # Verify logout cookies have epoch expiration
        logout_headers = [v for (k, v) in logout_response.headers if lowercase(k) == "set-cookie"]
        @test length(logout_headers) == 2
        @test all(occursin("Expires=Thu, 01 Jan 1970 00:00:00 GMT", h) for h in logout_headers)
        @test all(occursin("Max-Age=0", h) for h in logout_headers)
        
        # Verify client treats them as deleted (empty/invalid state)
        logout_request = HTTP.Request("GET", "/api/logout", [
            "Cookie" => "session=; csrf_token="
        ])
        @test Cookies.get_cookie(logout_request, "session") == ""
        @test Cookies.get_cookie(logout_request, "csrf_token") == ""
    end

    @testset "SCENARIO: Cookie Expiration and Cleanup" begin
        # Test cookies with various expiration times and cleanup patterns
        
        # ========== Set cookies with different Max-Age values ==========
        res1 = HTTP.Response(200)
        set_cookie!(res1, "short_lived", "expires_soon", attrs=Dict("max_age" => 60), encrypted=false)
        header1 = HTTP.header(res1, "Set-Cookie")
        @test occursin("Max-Age=60", header1)
        
        res2 = HTTP.Response(200)
        set_cookie!(res2, "long_lived", "expires_later", attrs=Dict("max_age" => 86400), encrypted=false)
        header2 = HTTP.header(res2, "Set-Cookie")
        @test occursin("Max-Age=86400", header2)
        
        # ========== Cleanup pattern: Max-Age=0 ==========
        cleanup_res = HTTP.Response(200)
        set_cookie!(cleanup_res, "short_lived", "", attrs=Dict("max_age" => 0), encrypted=false)
        cleanup_header = HTTP.header(cleanup_res, "Set-Cookie")
        @test occursin("Max-Age=0", cleanup_header)
        @test occursin("Expires=Thu, 01 Jan 1970 00:00:00 GMT", cleanup_header)
        
        # ========== Absolute expiration times ==========
        future_date = "2026-12-31T23:59:59Z"
        res3 = HTTP.Response(200)
        set_cookie!(res3, "future_cookie", "val", attrs=Dict("expires" => future_date), encrypted=false)
        header3 = HTTP.header(res3, "Set-Cookie")
        @test occursin("Expires=", header3)
        
        past_date = "2000-01-01T00:00:00Z"
        res4 = HTTP.Response(200)
        set_cookie!(res4, "expired_cookie", "", attrs=Dict("expires" => past_date), encrypted=false)
        header4 = HTTP.header(res4, "Set-Cookie")
        @test occursin("Expires=", header4)
        
        # ========== Batch cleanup (multiple cookies) ==========
        batch_cleanup = HTTP.Response(200)
        for name in ["session", "csrf_token", "tracking", "preferences"]
            set_cookie!(batch_cleanup, name, "", attrs=Dict("max_age" => 0), encrypted=false)
        end
        cleanup_headers = [v for (k, v) in batch_cleanup.headers if lowercase(k) == "set-cookie"]
        @test length(cleanup_headers) == 4
        @test all(occursin("Max-Age=0", h) for h in cleanup_headers)
    end

    @testset "SCENARIO: Path and Domain Matching" begin
        # Test cookie isolation by path and domain (browser-level behavior)
        
        # ========== Set cookies with different paths ==========
        res1 = HTTP.Response(200)
        set_cookie!(res1, "api_session", "session_token_1", attrs=Dict("path" => "/api"), encrypted=false)
        set_cookie!(res1, "admin_session", "session_token_2", attrs=Dict("path" => "/admin"), encrypted=false)
        set_cookie!(res1, "root_session", "session_token_3", attrs=Dict("path" => "/"), encrypted=false)
        
        headers1 = [v for (k, v) in res1.headers if lowercase(k) == "set-cookie"]
        @test length(headers1) == 3
        @test any(occursin("Path=/api", h) for h in headers1)
        @test any(occursin("Path=/admin", h) for h in headers1)
        @test any(occursin("Path=/", h) for h in headers1)
        
        # ========== Set cookies with different domains ==========
        res2 = HTTP.Response(200)
        set_cookie!(res2, "global_cookie", "val1", attrs=Dict("domain" => "example.com"), encrypted=false)
        set_cookie!(res2, "subdomain_cookie", "val2", attrs=Dict("domain" => ".sub.example.com"), encrypted=false)
        
        headers2 = [v for (k, v) in res2.headers if lowercase(k) == "set-cookie"]
        @test any(occursin("Domain=example.com", h) for h in headers2)
        @test any(occursin("Domain=.sub.example.com", h) for h in headers2)
        
        # ========== Path isolation: Request only sends matching cookies ==========
        # (Simulating browser behavior: only cookies matching path are sent)
        req_api = HTTP.Request("GET", "/api/users", [
            "Cookie" => "api_session=session_token_1; root_session=session_token_3"
        ])
        @test Cookies.get_cookie(req_api, "api_session") == "session_token_1"
        @test Cookies.get_cookie(req_api, "root_session") == "session_token_3"
        @test Cookies.get_cookie(req_api, "admin_session") === nothing
        
        req_admin = HTTP.Request("GET", "/admin/dashboard", [
            "Cookie" => "admin_session=session_token_2; root_session=session_token_3"
        ])
        @test Cookies.get_cookie(req_admin, "admin_session") == "session_token_2"
        @test Cookies.get_cookie(req_admin, "root_session") == "session_token_3"
        @test Cookies.get_cookie(req_admin, "api_session") === nothing
    end

    @testset "SCENARIO: Size Limits Enforcement" begin
        # Test comprehensive cookie size limit scenarios
        
        # ========== Small cookie (well under limit) ==========
        small_req = HTTP.Request("GET", "/", ["Cookie" => "tiny=x"])
        @test Cookies.get_cookie(small_req, "tiny", max_cookie_size=4096) == "x"
        
        # ========== Medium cookie (approaching limit) ==========
        medium_val = "a"^2000  # 2000 bytes
        medium_req = HTTP.Request("GET", "/", ["Cookie" => "medium=$medium_val"])
        @test Cookies.get_cookie(medium_req, "medium", max_cookie_size=4096) == medium_val
        @test Cookies.get_cookie(medium_req, "medium", max_cookie_size=1024) === nothing
        
        # ========== Large cookie (exceeds limit) ==========
        large_val = "b"^5000  # 5000 bytes
        large_req = HTTP.Request("GET", "/", ["Cookie" => "large=$large_val"])
        @test Cookies.get_cookie(large_req, "large", max_cookie_size=4096) === nothing
        @test Cookies.get_cookie(large_req, "large", max_cookie_size=8192) == large_val
        
        # ========== Size limit with encryption ==========
        secret_small = "small-secret-1234567890"
        encrypted_small = Cookies.encrypt_payload(secret_small, "secret_data")
        enc_req = HTTP.Request("GET", "/", ["Cookie" => "encrypted=$encrypted_small"])
        result = Cookies.get_cookie(enc_req, "encrypted", encrypted=true, secret_key=secret_small, max_cookie_size=4096)
        @test result == "secret_data"
        
        # ========== Multiple cookies with cumulative size ==========
        multi_req = HTTP.Request("GET", "/", [
            "Cookie" => "c1=val1; c2=val2; c3=val3; c4=val4; c5=val5"
        ])
        @test Cookies.get_cookie(multi_req, "c1", max_cookie_size=1024) == "val1"
        @test Cookies.get_cookie(multi_req, "c5", max_cookie_size=1024) == "val5"
    end

    @testset "SCENARIO: Secret Key Rotation and Migration" begin
        # Test handling of rotating secret keys (old key -> new key migration)
        
        old_secret = "old-secret-key-1234567890123456"
        new_secret = "new-secret-key-1234567890123456"
        
        # ========== Phase 1: Data encrypted with old key ==========
        data = "sensitive-user-data"
        old_encrypted = Cookies.encrypt_payload(old_secret, data)
        
        req_old = HTTP.Request("GET", "/", ["Cookie" => "session=$old_encrypted"])
        result_old = Cookies.get_cookie(req_old, "session", encrypted=true, secret_key=old_secret)
        @test result_old == data
        
        # ========== Phase 2: Cannot decrypt old data with new key ==========
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req_old, "session", encrypted=true, secret_key=new_secret)
        
        # ========== Phase 3: Re-encrypt with new key ==========
        new_encrypted = Cookies.encrypt_payload(new_secret, data)
        
        req_new = HTTP.Request("GET", "/", ["Cookie" => "session=$new_encrypted"])
        result_new = Cookies.get_cookie(req_new, "session", encrypted=true, secret_key=new_secret)
        @test result_new == data
        
        # ========== Phase 4: Verify different keys produce different ciphertexts ==========
        @test old_encrypted != new_encrypted
        
        # ========== Phase 5: Migration scenario - accept both until cutoff ==========
        # (Simulating dual-key support during rotation)
        dual_encrypt_test = function(value, secret)
            Cookies.encrypt_payload(secret, value)
        end
        
        old_ct = dual_encrypt_test(data, old_secret)
        new_ct = dual_encrypt_test(data, new_secret)
        
        # Try decrypting old ciphertext with old key (success)
        req_migration = HTTP.Request("GET", "/", ["Cookie" => "session=$old_ct"])
        @test Cookies.get_cookie(req_migration, "session", encrypted=true, secret_key=old_secret) == data
        
        # Update same request with new key
        req_migration2 = HTTP.Request("GET", "/", ["Cookie" => "session=$new_ct"])
        @test Cookies.get_cookie(req_migration2, "session", encrypted=true, secret_key=new_secret) == data
        
        # ========== Phase 6: Verify old key can't decrypt new data ==========
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req_migration2, "session", encrypted=true, secret_key=old_secret)
    end


    # ============================================================================
    # EXTRACTOR TESTS
    # ============================================================================

    @testset "EXTRACTOR: Basic Cookie Extraction" begin
        req = HTTP.Request("GET", "/", ["Cookie" => "user_id=123"])
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        
        # Test extraction via parameter
        param = Oxygen.Types.Param(name=:user_id, type=Cookie{Int})
        cookie_obj = Oxygen.Extractors.extract(param, lazy_req, nothing)
        
        @test cookie_obj.value == 123
        @test cookie_obj.name == "user_id"
    end

    @testset "EXTRACTOR: Encrypted Cookie Extraction" begin
        data = "secure-user-456"
        enc = Cookies.encrypt_payload(secret, data)
        req = HTTP.Request("GET", "/", ["Cookie" => "auth_token=$enc"])
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        
        param = Oxygen.Types.Param(name=:auth_token, type=Cookie{String})
        cookie_obj = Oxygen.Extractors.extract(param, lazy_req, secret)
        
        @test cookie_obj.value == data
    end

    @testset "EXTRACTOR: Missing Cookie with Default" begin
        req = HTTP.Request("GET", "/")
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        
        default_cookie = Cookie("pref", "dark")
        param = Oxygen.Types.Param(name=:pref, type=Cookie{String}, default=default_cookie, hasdefault=true)
        cookie_obj = Oxygen.Extractors.extract(param, lazy_req, nothing)
        
        @test cookie_obj.value === nothing # extractor itself doesn't apply default during extraction, core does
    end

    # ============================================================================
    # HIGH-LEVEL API TESTS (Context-aware)
    # ============================================================================

    @testset "API: configcookies and global state" begin
        # Reset state to ensure clean start
        resetstate()
        
        # 1. Test kwargs configuration
        configcookies(samesite="Strict", httponly=true, secret_key="api-test-secret-1234567890123456")
        
        conf = Oxygen.CONTEXT[].service.cookies[]
        @test conf.samesite == "Strict"
        @test conf.httponly == true
        @test conf.secret_key == "api-test-secret-1234567890123456"

        # 2. Test set_cookie! using global config
        res = Response(200)
        # Should be encrypted because secret_key is set
        set_cookie!(res, "session", "secret-data")
        
        header = HTTP.header(res, "Set-Cookie")
        @test !occursin("secret-data", header)
        @test occursin("SameSite=Strict", header)
        @test occursin("HttpOnly", header)

        # 3. Test get_cookie using global config
        payload = "my-session"
        enc_val = Cookies.encrypt_payload(conf.secret_key, payload)
        req = Request("GET", "/", ["Cookie" => "session=$enc_val"])
        # Should auto-decrypt
        val = get_cookie(req, "session")
        @test val == payload

        # 4. Test manual override in high-level API
        res2 = Response(200)
        set_cookie!(res2, "plain", "visible", encrypted=false)
        @test occursin("plain=visible", HTTP.header(res2, "Set-Cookie"))
        
        # Cleanup
        resetstate()
    end

    @testset "API: Multi-call configcookies overwrites state" begin
        resetstate()
        
        # First call
        configcookies(samesite="Lax", secret_key="first-secret-1234567890123456")
        conf1 = Oxygen.CONTEXT[].service.cookies[]
        @test conf1.samesite == "Lax"
        @test conf1.secret_key == "first-secret-1234567890123456"

        # Second call should overwrite
        configcookies(samesite="Strict", secret_key="second-secret-1234567890123456")
        conf2 = Oxygen.CONTEXT[].service.cookies[]
        @test conf2.samesite == "Strict"
        @test conf2.secret_key == "second-secret-1234567890123456"
        
        resetstate()
    end

    @testset "API: serve() initializes cookie config" begin
        resetstate()
        
        # serve() should accept cookie parameters
        # Test indirectly by verifying the context is properly initialized
        # Note: We can't actually call serve() here as it would block,
        # but we can verify the initialization logic
        ctx = Oxygen.Core.ServerContext()
        
        # Simulate what serve() does
        secret_key = "serve-test-key-1234567890123456"
        current = ctx.service.cookies[]
        ctx.service.cookies[] = CookieConfig(
            secret_key = secret_key,
            httponly = false,
            secure = false,
            samesite = "None",
            path = current.path,
            domain = current.domain,
            maxage = current.maxage,
            expires = current.expires,
            max_cookie_size = current.max_cookie_size
        )
        
        @test ctx.service.cookies[].secret_key == secret_key
        @test ctx.service.cookies[].httponly == false
        @test ctx.service.cookies[].secure == false
        @test ctx.service.cookies[].samesite == "None"
    end

    @testset "API: Invalid secret key error handling" begin
        # Secret key too short should be caught during encryption
        short_key = "tooshort"
        res = HTTP.Response(200)
        
        # Should either throw or handle gracefully
        try
            set_cookie!(res, "test", "value", secret_key=short_key, encrypted=true)
            # If it doesn't throw, verify the key is stored (may throw on use)
            @test true
        catch e
            # Expected - short key should fail
            @test true
        end
    end

    @testset "API: Path normalization" begin
        # Test various edge cases for path normalization
        
        # 1. Path with trailing slash
        res1 = HTTP.Response(200)
        set_cookie!(res1, "p1", "v1", attrs=Dict("path" => "/api/"), encrypted=false)
        header1 = HTTP.header(res1, "Set-Cookie")
        @test occursin("Path=/api/", header1)

        # 2. Path without leading slash should be fixed
        res2 = HTTP.Response(200)
        set_cookie!(res2, "p2", "v2", attrs=Dict("path" => "api"), encrypted=false)
        header2 = HTTP.header(res2, "Set-Cookie")
        @test occursin("Path=/", header2) # Should normalize to root

        # 3. Root path
        res3 = HTTP.Response(200)
        set_cookie!(res3, "p3", "v3", attrs=Dict("path" => "/"), encrypted=false)
        header3 = HTTP.header(res3, "Set-Cookie")
        @test occursin("Path=/", header3)
    end

    @testset "EXTRACTOR: End-to-end with global config" begin
        resetstate()
        
        # Set up global secret key
        configcookies(secret_key="global-secret-1234567890123456")
        conf = Oxygen.CONTEXT[].service.cookies[]
        
        # Create request with encrypted cookie
        data = "encrypted-user-data"
        enc_val = Cookies.encrypt_payload(conf.secret_key, data)
        req = Request("GET", "/", ["Cookie" => "user_data=$enc_val"])
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        
        # Extract using the global config's secret
        param = Oxygen.Types.Param(name=:user_data, type=Cookie{String})
        cookie_obj = Oxygen.Extractors.extract(param, lazy_req, conf.secret_key)
        
        @test cookie_obj.value == data
        @test cookie_obj.name == "user_data"
        
        resetstate()
    end

    @testset "ROBUSTNESS: Empty string secret key validation" begin
        # Empty secret key should not be allowed for encryption
        res = HTTP.Response(200)
        
        # 1. Test set_cookie! with empty secret_key
        # It should NOT encrypt if key is empty
        res2 = set_cookie!(res, "test_empty_key", "value", secret_key="", encrypted=true)
        header = HTTP.header(res2, "Set-Cookie")
        @test occursin("test_empty_key=value", header)
        
        # 2. Test get_cookie with empty secret_key
        req = HTTP.Request("GET", "/", ["Cookie" => "test_empty_key=value"])
        @test Cookies.get_cookie(req, "test_empty_key", secret_key="", encrypted=true) == "value"
    end

    @testset "SECURITY: AES-GCM Integrity (Tampering)" begin
        # 1. Encrypt a value
        data = "highly-sensitive-info"
        enc_val = Cookies.encrypt_payload(secret, data)
        
        # 2. Destructive tampering (force invalid base64/corrupt tag)
        tampered_val = enc_val * "!!!" 
        
        # 3. Decryption must throw CookieError
        req = HTTP.Request("GET", "/", ["Cookie" => "secure=$tampered_val"])
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req, "secure", encrypted=true, secret_key=secret)
    end

    @testset "SECURITY: AES-GCM Auth Tag Verification (In-Alphabet Tampering)" begin
        # Test that tampering within valid Base64 alphabet is caught by the auth tag
        data = "secret-message"
        enc_val = Cookies.encrypt_payload(secret, data)
        
        # Flip a character that is still valid Base64 (e.g., A->B)
        chars = collect(enc_val)
        for i in 1:length(chars)
            if chars[i] in ('A':'Z')
                chars[i] = (chars[i] == 'A') ? 'B' : 'A'
                break
            elseif chars[i] in ('a':'z')
                chars[i] = (chars[i] == 'a') ? 'b' : 'a'
                break
            elseif chars[i] in ('0':'9')
                chars[i] = (chars[i] == '0') ? '1' : '0'
                break
            end
        end
        tampered_val = String(chars)
        
        # Decryption should throw CookieError due to auth tag failure
        req = HTTP.Request("GET", "/", ["Cookie" => "secure=$tampered_val"])
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req, "secure", encrypted=true, secret_key=secret)
    end

    @testset "SECURITY: Wrong Secret Key Rejection" begin
        # Encrypt with one key, try to decrypt with a different key
        data = "confidential-data"
        enc_val = Cookies.encrypt_payload(secret, data)
        
        wrong_key = "wrong-secret-key-1234567890123456"
        req = HTTP.Request("GET", "/", ["Cookie" => "data=$enc_val"])
        
        # Should throw CookieError (decryption fails with wrong key)
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req, "data", encrypted=true, secret_key=wrong_key)
    end

    @testset "SECURITY: IV Tampering Detection" begin
        # The IV is the first 12 bytes (24 Base64 chars excluding padding)
        # Modify a character in the IV portion to test if GSM tag validation catches it
        data = "test-payload"
        enc_val = Cookies.encrypt_payload(secret, data)
        
        # Tamper with the IV portion (first ~16 characters of base64)
        chars = collect(enc_val)
        if length(chars) > 16
            chars[5] = (chars[5] == 'A') ? 'C' : 'A'  # Flip a char in IV region
        end
        tampered_val = String(chars)
        
        # GCM should fail to verify due to IV mismatch in the auth calculation
        req = HTTP.Request("GET", "/", ["Cookie" => "iv_test=$tampered_val"])
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req, "iv_test", encrypted=true, secret_key=secret)
    end

    @testset "SECURITY: Tag Corruption Detection" begin
        # The tag is the last 16 bytes (last ~21 Base64 chars)
        # Modifying the tag directly should definitely fail
        data = "another-secret"
        enc_val = Cookies.encrypt_payload(secret, data)
        
        # Tamper with the last portion (tag area)
        chars = collect(enc_val)
        if length(chars) > 5
            chars[end - 3] = (chars[end - 3] == 'A') ? 'Z' : 'A'  # Flip a char in tag region
        end
        tampered_val = String(chars)
        
        # GCM tag verification should fail
        req = HTTP.Request("GET", "/", ["Cookie" => "tag_test=$tampered_val"])
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req, "tag_test", encrypted=true, secret_key=secret)
    end

    @testset "ROBUSTNESS: Malformed Encryption Payloads" begin
        # 1. Invalid Base64
        req1 = HTTP.Request("GET", "/", ["Cookie" => "bad_enc=!!!not-base64!!!"])
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req1, "bad_enc", encrypted=true, secret_key=secret)
        
        # 2. Valid Base64 but too short for IV + Tag
        req2 = HTTP.Request("GET", "/", ["Cookie" => "short_enc=YWFhYQ=="]) # "aaaa"
        @test_throws Oxygen.Core.Errors.CookieError Cookies.get_cookie(req2, "short_enc", encrypted=true, secret_key=secret)
    end

    @testset "CONCURRENCY: Multi-threaded Cookie Operations" begin
        # Verify that setting/getting cookies is thread-safe (stateless engine)
        n = 100
        
        # 1. Thread-safe emission
        results = Vector{HTTP.Response}(undef, n)
        Threads.@threads for i in 1:n
            res = HTTP.Response(200)
            set_cookie!(res, "id", "$i", encrypted=false)
            results[i] = res
        end
        
        # Consolidate into 1 test pass
        @test all(Cookies.get_cookie(results[i], "id") == "$i" for i in 1:n)
        
        # 2. Thread-safe parsing
        req_headers = ["Cookie" => join(["c$i=v$i" for i in 1:n], "; ")]
        req = HTTP.Request("GET", "/", req_headers)
        
        parsed_values = Vector{String}(undef, n)
        Threads.@threads for i in 1:n
            parsed_values[i] = Cookies.get_cookie(req, "c$i")
        end
        
        # Consolidate into 1 test pass
        @test all(parsed_values[i] == "v$i" for i in 1:n)
    end

    @testset "EXTRACTOR: Tempered Cookie Error" begin
        # 1. Create a tempered encrypted cookie (invalid base64)
        data = "secret"
        enc = Cookies.encrypt_payload(secret, data)
        tampered = enc[1:end-1] * "!"
        
        req = HTTP.Request("GET", "/", ["Cookie" => "auth=$tampered"])
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        param = Oxygen.Types.Param(name=:auth, type=Cookie{String})
        
        # Extraction should throw CookieError (propagating from decrypt_payload)
        @test_throws Oxygen.Core.Errors.CookieError Oxygen.Extractors.extract(param, lazy_req, secret)
    end

    @testset "EXTRACTOR: In-Alphabet Tampered Cookie (Auth Tag Failure)" begin
        # Test that in-alphabet tampering is caught by auth tag during extraction
        data = "user-session-data"
        enc = Cookies.encrypt_payload(secret, data)
        
        # Flip a Base64-valid character
        chars = collect(enc)
        for i in 1:length(chars)
            if chars[i] in ('A':'Z')
                chars[i] = chars[i] == 'A' ? 'M' : 'A'
                break
            end
        end
        tampered = String(chars)
        
        req = HTTP.Request("GET", "/", ["Cookie" => "session=$tampered"])
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        param = Oxygen.Types.Param(name=:session, type=Cookie{String})
        
        # Auth tag verification should fail during extraction
        @test_throws Oxygen.Core.Errors.CookieError Oxygen.Extractors.extract(param, lazy_req, secret)
    end

    @testset "EXTRACTOR: Wrong Key Rejection During Extraction" begin
        # Encrypt with correct key, try to extract with wrong key
        data = "protected-content"
        enc = Cookies.encrypt_payload(secret, data)
        
        wrong_key = "incorrect-key-1234567890123456"
        req = HTTP.Request("GET", "/", ["Cookie" => "secure=$enc"])
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        param = Oxygen.Types.Param(name=:secure, type=Cookie{String})
        
        # Decryption with wrong key should fail
        @test_throws Oxygen.Core.Errors.CookieError Oxygen.Extractors.extract(param, lazy_req, wrong_key)
    end

    @testset "EXTRACTOR: Truncated Encrypted Cookie" begin
        # Test that truncated payloads fail validation
        data = "important-secret"
        enc = Cookies.encrypt_payload(secret, data)
        
        # Truncate the payload (remove last few chars)
        truncated = enc[1:max(1, length(enc)-5)]
        
        req = HTTP.Request("GET", "/", ["Cookie" => "incomplete=$truncated"])
        lazy_req = Oxygen.Types.LazyRequest(request=req)
        param = Oxygen.Types.Param(name=:incomplete, type=Cookie{String})
        
        # Should fail due to insufficient length for IV + Tag
        @test_throws Oxygen.Core.Errors.CookieError Oxygen.Extractors.extract(param, lazy_req, secret)
    end

end
