# """
#     OxygenCryptoExt Tests
#     julia --project=test test/extensions/cryptotests.jl
# """

# if !isdefined(Main, :Oxygen)
#     include(joinpath(@__DIR__, "..", "common_setup.jl"))
#     # Trigger extensions needed for these tests
#     trigger_extension("OpenSSL")
#     trigger_extension("SHA")
# end

using Oxygen
using Test
using OpenSSL
using SHA
using Base64

@testset "OxygenCryptoExt Tests" begin

    secret = "super-secret-key"
    payload = "sensitive-user-data-123"

    @testset "Basic Encrypt/Decrypt" begin
        # extension should be loaded since we imported OpenSSL in this test
        encrypted = Oxygen.Cookies.encrypt_payload(secret, payload)
        
        @test encrypted != payload
        @test !isempty(encrypted)
        
        decrypted = Oxygen.Cookies.decrypt_payload(secret, encrypted)
        @test decrypted == payload
    end

    @testset "Base64URL Validity" begin
        encrypted = Oxygen.Cookies.encrypt_payload(secret, payload)
        
        # Check that it doesn't contain standard Base64 chars that are problematic in URLs/Cookies
        @test !contains(encrypted, "+")
        @test !contains(encrypted, "/")
        @test !contains(encrypted, "=")
    end

    @testset "Integrity Check (Tampering)" begin
        encrypted = Oxygen.Cookies.encrypt_payload(secret, payload)
        
        # Tamper with the ciphertext (Base64 encoded)
        # We replace one valid Base64URL char with another at the end
        chars = collect(encrypted)
        chars[end] = chars[end] == 'A' ? 'B' : 'A'
        tampered = join(chars)
        
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload(secret, tampered)
    end

    @testset "Invalid Secret" begin
        encrypted = Oxygen.Cookies.encrypt_payload(secret, payload)
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload("wrong-secret", encrypted)
    end

    @testset "Malformed Payloads" begin
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload(secret, "not-base64-!@#\$")
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload(secret, "abcd") # too short
    end

    @testset "Large Payloads" begin
        large_payload = "a" ^ 10_000
        encrypted = Oxygen.Cookies.encrypt_payload(secret, large_payload)
        decrypted = Oxygen.Cookies.decrypt_payload(secret, encrypted)
        @test decrypted == large_payload
    end

    @testset "Non-Determinism (IV Randomization)" begin
        # Encrypting the same thing twice should yield different results due to random IV
        enc1 = Oxygen.Cookies.encrypt_payload(secret, payload)
        enc2 = Oxygen.Cookies.encrypt_payload(secret, payload)
        @test enc1 != enc2
        @test Oxygen.Cookies.decrypt_payload(secret, enc1) == payload
        @test Oxygen.Cookies.decrypt_payload(secret, enc2) == payload
    end

    @testset "Unicode & Special Characters" begin
        unicode_payload = "🚀 Oxygen.jl is fast! ⚡ (ñ, ü, 中文)"
        encrypted = Oxygen.Cookies.encrypt_payload(secret, unicode_payload)
        decrypted = Oxygen.Cookies.decrypt_payload(secret, encrypted)
        @test decrypted == unicode_payload
    end

    @testset "Empty Payload" begin
        empty_payload = ""
        encrypted = Oxygen.Cookies.encrypt_payload(secret, empty_payload)
        decrypted = Oxygen.Cookies.decrypt_payload(secret, encrypted)
        @test decrypted == empty_payload
    end

    @testset "Base64URL Padding Symmetry" begin
        # Test strings of different lengths to trigger 0, 1, 2 pad variations in the manual decoder
        for len in 1:10
            p = "x" ^ len
            enc = Oxygen.Cookies.encrypt_payload(secret, p)
            @test Oxygen.Cookies.decrypt_payload(secret, enc) == p
        end
    end

    @testset "Key Derivation Consistency" begin
        # Same secret should always produce same encryption (deterministic key derivation)
        # Note: IV is random, so encrypted values differ, but decryption with same key succeeds
        secret_consistent = "consistent-key-for-derivation"
        payload1 = "data1"
        payload2 = "data2"
        
        enc1a = Oxygen.Cookies.encrypt_payload(secret_consistent, payload1)
        enc1b = Oxygen.Cookies.encrypt_payload(secret_consistent, payload1)
        
        # Both encrypt to different ciphertexts (different IVs) but both decrypt correctly
        @test enc1a != enc1b
        @test Oxygen.Cookies.decrypt_payload(secret_consistent, enc1a) == payload1
        @test Oxygen.Cookies.decrypt_payload(secret_consistent, enc1b) == payload1
        
        # Different payloads produce different ciphertexts
        enc2 = Oxygen.Cookies.encrypt_payload(secret_consistent, payload2)
        @test enc2 != enc1a
        @test enc2 != enc1b
    end

    @testset "IV Uniqueness Protection" begin
        # Verify that sequential encryptions use different IVs
        payload_iv = "test-payload-for-iv"
        
        encrypted_values = [Oxygen.Cookies.encrypt_payload(secret, payload_iv) for _ in 1:10]
        
        # All encrypted values should be unique (due to random IV)
        @test length(unique(encrypted_values)) == 10
        
        # But all should decrypt to same value
        decrypted_values = [Oxygen.Cookies.decrypt_payload(secret, enc) for enc in encrypted_values]
        @test all(dv == payload_iv for dv in decrypted_values)
    end

    @testset "Thread-Safe Concurrent Operations" begin
        # Test concurrent encrypt/decrypt in multiple threads
        n_threads = 10
        n_ops = 20
        
        results = Vector{String}(undef, n_threads * n_ops)
        payloads = ["payload_$i" for i in 1:(n_threads * n_ops)]
        
        # Concurrent encryption
        Threads.@threads for i in 1:(n_threads * n_ops)
            enc = Oxygen.Cookies.encrypt_payload(secret, payloads[i])
            results[i] = enc
        end
        
        # Concurrent decryption
        decrypted = Vector{String}(undef, n_threads * n_ops)
        Threads.@threads for i in 1:(n_threads * n_ops)
            decrypted[i] = Oxygen.Cookies.decrypt_payload(secret, results[i])
        end
        
        # Verify all decrypted correctly
        @test all(decrypted[i] == payloads[i] for i in 1:(n_threads * n_ops))
    end

    @testset "IV Region Tampering Specific" begin
        # Test that tampering specifically in the IV region (first 12 bytes) is detected
        encrypted = Oxygen.Cookies.encrypt_payload(secret, payload)
        
        # IV is the first ~16 Base64 characters (12 bytes = 16 Base64 chars)
        chars = collect(encrypted)
        
        # Tamper with first character (guaranteed to be in IV region)
        chars[1] = chars[1] == 'A' ? 'B' : 'A'
        tampered_iv = join(chars)
        
        # Should fail due to IV mismatch in GCM authentication
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload(secret, tampered_iv)
    end

    @testset "Auth Tag Tampering Detection" begin
        # Test that tampering in the authentication tag is detected
        encrypted = Oxygen.Cookies.encrypt_payload(secret, payload)
        
        # Auth tag is the last ~21 Base64 characters (16 bytes)
        chars = collect(encrypted)
        
        # Flip a character in the tag region (last character)
        chars[end] = chars[end] == 'A' ? 'Z' : 'A'
        tampered_tag = join(chars)
        
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload(secret, tampered_tag)
    end

    @testset "Short Secret Key Handling" begin
        # Test handling of very short secret keys (edge case)
        # The system should still work, though key derivation happens
        short_key = "short"
        payload_short = "data-with-short-key"
        
        # Should not throw during encryption
        encrypted_short = Oxygen.Cookies.encrypt_payload(short_key, payload_short)
        @test !isempty(encrypted_short)
        
        # Should decrypt correctly
        decrypted_short = Oxygen.Cookies.decrypt_payload(short_key, encrypted_short)
        @test decrypted_short == payload_short
        
        # But wrong short key should fail
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload("wrong", encrypted_short)
    end

    @testset "Ciphertext Structure Validation" begin
        # Validate the Basic structure of encrypted output
        # Expected: Base64URL-encoded (IV || ciphertext || auth_tag)
        encrypted = Oxygen.Cookies.encrypt_payload(secret, payload)
        
        # Should be non-empty Base64URL string
        @test !isempty(encrypted)
        @test isa(encrypted, String)
        
        # Should only contain Base64URL characters (no +, /, =)
        @test !contains(encrypted, "+")
        @test !contains(encrypted, "/")
        @test !contains(encrypted, "=")
        
        # Should be decodable as Base64
        try
            # Convert Base64URL to standard Base64 for validation
            std_b64 = replace(encrypted, '-' => '+', '_' => '/')
            padding = length(std_b64) % 4
            if padding > 0
                std_b64 *= "=" ^ (4 - padding)
            end
            decoded = base64decode(std_b64)
            @test length(decoded) >= 28  # At least IV (12) + Tag (16)
        catch
            @test false  # Should not fail Base64 decode
        end
    end

    @testset "Decryption State Consistency" begin
        # Test that decryption doesn't have side effects
        payload_state = "state-test-payload"
        encrypted_state = Oxygen.Cookies.encrypt_payload(secret, payload_state)
        
        # Decrypt multiple times, should always succeed
        for _ in 1:5
            result = Oxygen.Cookies.decrypt_payload(secret, encrypted_state)
            @test result == payload_state
        end
        
        # Interleaved encrypt/decrypt should maintain state
        p1 = "first"
        p2 = "second"
        enc1 = Oxygen.Cookies.encrypt_payload(secret, p1)
        enc2 = Oxygen.Cookies.encrypt_payload(secret, p2)
        
        # Decrypt in mixed order
        @test Oxygen.Cookies.decrypt_payload(secret, enc2) == p2
        @test Oxygen.Cookies.decrypt_payload(secret, enc1) == p1
        @test Oxygen.Cookies.decrypt_payload(secret, enc2) == p2
    end

    @testset "Multiple Secrets Isolation" begin
        # Test that data encrypted with one secret cannot be decrypted with another
        secret1 = "secret-one-1234567890"
        secret2 = "secret-two-1234567890"
        payload_isolation = "isolated-message"
        
        enc_with_secret1 = Oxygen.Cookies.encrypt_payload(secret1, payload_isolation)
        
        # Should decrypt with correct secret
        @test Oxygen.Cookies.decrypt_payload(secret1, enc_with_secret1) == payload_isolation
        
        # Should NOT decrypt with wrong secret
        @test_throws Oxygen.Errors.CookieError Oxygen.Cookies.decrypt_payload(secret2, enc_with_secret1)
    end

    @testset "Null Byte Handling" begin
        # Test payloads containing null bytes
        payload_null = "data\0with\0nulls"
        encrypted_null = Oxygen.Cookies.encrypt_payload(secret, payload_null)
        decrypted_null = Oxygen.Cookies.decrypt_payload(secret, encrypted_null)
        
        @test decrypted_null == payload_null
        @test contains(decrypted_null, "\0")
    end

end
