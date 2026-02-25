module SecurityTests
using Oxygen
using Test
using HTTP

@testset "Security: Missing Extension Robustness" begin
    
    # We can detect if the extension is loaded by checking for specific methods
    # or using Base.get_extension (Julia 1.9+)
    is_extension_loaded = !isnothing(Base.get_extension(Oxygen, :OxygenCryptoExt))

    if !is_extension_loaded
        # Case 1: Extension is NOT loaded.
        # Encryption/Decryption MUST throw CookieError to prevent silent plaintext leak.
        res = HTTP.Response(200)
        @test_throws Errors.CookieError set_cookie!(res, "session", "secret-data", secret_key="my-key")
        
        req = HTTP.Request("GET", "/", ["Cookie" => "session=some-data"])
        @test_throws Errors.CookieError get_cookie(req, "session", encrypted=true, secret_key="my-key")
    else
        # Case 2: Extension IS loaded (e.g. during Pkg.test() where OpenSSL is present).
        # We can still verify the placeholder logic by calling it with non-String types 
        # that the extension doesn't override (it only overrides String/String).
        
        @testset "Placeholder Logic (Extension Loaded)" begin
            # Using a Symbol for secret should bypass the extension's String-specific method
            @test_throws Errors.CookieError Oxygen.Cookies.encrypt_payload(:secret, "data")
            @test_throws Errors.CookieError Oxygen.Cookies.decrypt_payload(:secret, "data")
        end
    end
end

end
