using Pkg
using Test

println("--- DIAGNOSTIC START ---")

try
    println("1. Setting up Environment")
    Pkg.activate(; temp=true)

    println("2. Adding OpenSSL")
    Pkg.add("OpenSSL")
    import OpenSSL
    println("OpenSSL Loaded. UUID: ", Base.PkgId(OpenSSL).uuid)

    println("3. Developing Oxygen")
    Pkg.develop(path=abspath("."))

    println("4. Loading Oxygen")
    import Oxygen
    println("Oxygen Loaded.")

    println("5. Checking Extension")
    secret = "test"
    payload = "hello"
    try
        res = Oxygen.Cookies.encrypt_payload(secret, payload)
        println("Encrypt result: ", res)
        if res == payload
            println("EXTENSION NOT LOADED (returned plaintext)")
        else
            println("EXTENSION LOADED (returned ciphertext)")
        end
    catch e
        println("Error calling encrypt_payload: ", e)
    end

catch e
    println("ERROR OCCURRED:")
    showerror(stdout, e, catch_backtrace())
end
