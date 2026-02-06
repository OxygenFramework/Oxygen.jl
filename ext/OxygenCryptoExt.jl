module OxygenCryptoExt

using Oxygen
using OpenSSL
using Base64
using SHA

"""
    encrypt_payload(secret::String, payload::String)

Encrypts a payload using AES-256-GCM.
- Key is derived from `SHA256(secret)`.
- A random 12-byte IV is generated.
- Returns a Base64 encoded string: `base64(iv + ciphertext + tag)`.
"""
function Oxygen.Cookies.encrypt_payload(secret::String, payload::String)
    # Derive 32-byte key
    key = SHA.sha256(secret)

    # Generate 12-byte IV
    iv = Vector{UInt8}(undef, 12)
    OpenSSL.RAND_bytes!(iv)

    # Setup Cipher
    cipher = OpenSSL.Cipher("AES-256-GCM")
    ctx = OpenSSL.EncryptCipherContext(cipher, key, iv)

    # Encrypt
    # For GCM, we don't need manual padding, but OpenSSL.jl might handle block updates.
    # However, OpenSSL.jl's high-level API might be slightly different.
    # Let's use the streaming API or block API safely.

    # Update
    ciphertext_part1 = OpenSSL.update(ctx, Vector{UInt8}(payload))
    # Finalize (GCM usually has no output in final but calculates tag)
    ciphertext_part2 = OpenSSL.final(ctx)

    ciphertext = [ciphertext_part1; ciphertext_part2]

    # Get Tag (default 16 bytes)
    tag = OpenSSL.get_tag(ctx)

    # Combine: IV (12) + Ciphertext (N) + Tag (16)
    final_data = [iv; ciphertext; tag]

    return Base64.base64encode(final_data)
end

"""
    decrypt_payload(secret::String, payload::String)

Decrypts a payload using AES-256-GCM.
- Expects Base64 input: `[IV(12)][Ciphertext][Tag(16)]`.
- Verifies the tag (integrity check).
- Returns the decrypted string.
- Throws error if decryption/verification fails.
"""
function Oxygen.Cookies.decrypt_payload(secret::String, payload::String)
    # Decode Base64
    data = try
        Base64.base64decode(payload)
    catch
        error("Invalid Base64 payload")
    end

    # Validate minimum length (IV + Tag = 28 bytes)
    if length(data) < 28
        error("Payload too short")
    end

    # Extract parts
    iv = data[1:12]
    tag = data[end-15:end]
    ciphertext = data[13:end-16]

    # Derive Key
    key = SHA.sha256(secret)

    # Setup Cipher
    cipher = OpenSSL.Cipher("AES-256-GCM")
    ctx = OpenSSL.DecryptCipherContext(cipher, key, iv)

    # Set Tag for verification BEFORE final
    OpenSSL.set_tag(ctx, tag)

    # Decrypt
    plaintext_part1 = OpenSSL.update(ctx, ciphertext)

    # Check verification in final
    plaintext_part2 = try
        OpenSSL.final(ctx)
    catch e
        # OpenSSL throws if tag verification fails
        error("Decryption failed: integrity check failed")
    end

    return String([plaintext_part1; plaintext_part2])
end

end
