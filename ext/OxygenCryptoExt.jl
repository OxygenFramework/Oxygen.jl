module OxygenCryptoExt

using OpenSSL
using SHA
using Base64
import Oxygen.Core.Cookies: encrypt_payload, decrypt_payload
import Oxygen.Core.Errors: CookieError

# Helper for URL-safe Base64
function base64url_encode(data::Vector{UInt8})
    s = base64encode(data)
    s = replace(s, '+' => '-', '/' => '_')
    return replace(s, '=' => "")
end

function base64url_decode(s::String)
    s = replace(s, '-' => '+', '_' => '/')
    padding = length(s) % 4
    if padding > 0
        s *= "=" ^ (4 - padding)
    end
    return base64decode(s)
end

function encrypt_payload(secret::String, payload::String)
    key = SHA.sha256(secret)
    
    # Use OpenSSL for a cryptographically secure IV
    iv = Vector{UInt8}(undef, 12)
    ccall((:RAND_bytes, OpenSSL.libcrypto), Cint, (Ptr{UInt8}, Cint), iv, 12)

    cipher_ptr = ccall((:EVP_get_cipherbyname, OpenSSL.libcrypto), Ptr{Cvoid}, (Cstring,), "AES-256-GCM")
    cipher = OpenSSL.EvpCipher(cipher_ptr)
    ctx = OpenSSL.EvpCipherContext()
    
    try
        OpenSSL.encrypt_init(ctx, cipher, key, iv)
        ciphertext = OpenSSL.cipher_update(ctx, Vector{UInt8}(payload))
        final_part = OpenSSL.cipher_final(ctx)

        tag = Vector{UInt8}(undef, 16)
        ccall((:EVP_CIPHER_CTX_ctrl, OpenSSL.libcrypto), Cint, 
              (OpenSSL.EvpCipherContext, Cint, Cint, Ptr{UInt8}), 
              ctx, 0x10, 16, tag)

        return base64url_encode(vcat(iv, ciphertext, final_part, tag))
    finally
        # context cleaned by finalizer
    end
end

function decrypt_payload(secret::String, payload::String)
    data = try
        base64url_decode(payload)
    catch
        throw(CookieError("Invalid Base64 payload"))
    end

    if length(data) < 28
        throw(CookieError("Payload too short"))
    end

    iv = data[1:12]
    tag = data[end-15:end]
    ciphertext = data[13:end-16]
    key = SHA.sha256(secret)

    cipher_ptr = ccall((:EVP_get_cipherbyname, OpenSSL.libcrypto), Ptr{Cvoid}, (Cstring,), "AES-256-GCM")
    cipher = OpenSSL.EvpCipher(cipher_ptr)
    ctx = OpenSSL.EvpCipherContext()

    try
        OpenSSL.decrypt_init(ctx, cipher, key, iv)
        plaintext = OpenSSL.cipher_update(ctx, Vector{UInt8}(ciphertext))

        ccall((:EVP_CIPHER_CTX_ctrl, OpenSSL.libcrypto), Cint, 
              (OpenSSL.EvpCipherContext, Cint, Cint, Ptr{UInt8}), 
              ctx, 0x11, 16, Vector{UInt8}(tag))

        final_res = Vector{UInt8}(undef, 16)
        outlen = Ref{Cint}(0)
        
        # EVP_DecryptFinal_ex returns 1 on success
        ret = ccall((:EVP_DecryptFinal_ex, OpenSSL.libcrypto), Cint,
                    (OpenSSL.EvpCipherContext, Ptr{UInt8}, Ptr{Cint}),
                    ctx, final_res, outlen)
        
        if ret != 1
            throw(CookieError("Decryption failed: integrity check failed"))
        end

        return String(vcat(plaintext, final_res[1:outlen[]]))
    catch e
        if e isa CookieError; rethrow(e); end
        throw(CookieError("Decryption error: $(e)"))
    end
end

end
