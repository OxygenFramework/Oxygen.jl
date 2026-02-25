module SessionTests
# To run just this test, uncomment below code and run: julia --project=test/dev_project test/sessiontests.jl
# if !isdefined(Main, :Oxygen)
#     include(joinpath(@__DIR__, "common_setup.jl"))
#     # Trigger extensions needed for these tests
#     trigger_extension("OpenSSL")
#     trigger_extension("SHA")
# end

using Oxygen
using Oxygen.Types
using Test
using HTTP

struct User
    id::Int
    name::String
end

@testset "Oxygen Session via App Context Tests" begin

    # 1. Setup a simple store in App Context
    session_store = Dict{String, User}()
    user1 = User(1, "John Doe")
    session_store["session-abc-123"] = user1

    # 2. Define a route that uses the Session extractor
    # By default, it looks for a cookie named "session"
    @get "/profile" function(req, session::Session{User})
        if isnothing(session.payload)
            return "Unauthorized"
        end
        return "Hello $(session.payload.name)"
    end

    @testset "Valid Session" begin
        # Create a request with the session cookie
        req = Request("GET", "/profile", ["Cookie" => "session=session-abc-123"])
        res = internalrequest(req; context=session_store)
        @test text(res) == "Hello John Doe"
    end

    @testset "Invalid Session ID" begin
        req = Request("GET", "/profile", ["Cookie" => "session=wrong-id"])
        res = internalrequest(req; context=session_store)
        @test text(res) == "Unauthorized"
    end

    @testset "Missing Session Cookie" begin
        req = Request("GET", "/profile")
        res = internalrequest(req; context=session_store)
        @test text(res) == "Unauthorized"
    end

    @testset "Custom Cookie Name" begin
        # Define a route with a custom cookie name
        @get "/custom" function(req, session = Session{User}("auth_token"))
            if isnothing(session.payload)
                return "Unauthorized"
            end
            return "ID: $(session.payload.id)"
        end

        req = Request("GET", "/custom", ["Cookie" => "auth_token=session-abc-123"])
        res = internalrequest(req; context=session_store)
        @test text(res) == "ID: 1"
    end

    @testset "Encrypted Session Cookie" begin
        # Setup encryption
        secret = "a" ^ 32
        configcookies(secret_key=secret)

        # We need to encrypt the session ID "session-abc-123"
        # Since encrypt_payload is internal, we can use it or just test the round-trip
        
        @get "/login-success" function()
            res = Response("Logged in")
            set_cookie!(res, "session", "session-abc-123", encrypted=true)
            return res
        end

        # 1. Login to get the encrypted cookie
        login_res = internalrequest(Request("GET", "/login-success"))
        cookie_header = HTTP.header(login_res, "Set-Cookie")
        
        # 2. Use that cookie to access profile
        req = Request("GET", "/profile", ["Cookie" => cookie_header])
        profile_res = internalrequest(req; context=session_store)
        
        @test text(profile_res) == "Hello John Doe"

        # Cleanup
        configcookies(secret_key=nothing)
    end

    @testset "MemoryStore with TTL and Pruning" begin
        # Ensure encryption is off for this test
        configcookies(secret_key=nothing)

        # Create a typed MemoryStore
        store = MemoryStore{String, User}()
        user = User(5, "TTL User")
        
        # 1. Store with short TTL (1 second)
        # We need to use Cookies.storesession! since it's in that module
        Oxygen.Cookies.storesession!(store, "temp-id", user, ttl=1)
        
        @get "/ttl-profile" function(req, session::Session{User})
            if isnothing(session.payload)
                return "Expired"
            end
            return "Active"
        end

        # Immediate check
        res1 = internalrequest(Request("GET", "/ttl-profile", ["Cookie" => "session=temp-id"]); context=store)
        @test text(res1) == "Active"

        # Wait for expiration
        sleep(1.1)
        res2 = internalrequest(Request("GET", "/ttl-profile", ["Cookie" => "session=temp-id"]); context=store)
        @test text(res2) == "Expired"

        # 2. Verify Pruning
        @test length(store.data) == 1
        Oxygen.Cookies.prunesessions!(store)
        @test length(store.data) == 0
    end

    @testset "MemoryStore Thread Safety" begin
        store = MemoryStore{Int, String}()
        n = 1000
        
        # Concurrent writes
        @sync for i in 1:n
            Threads.@spawn Oxygen.Cookies.storesession!(store, i, "user-$i")
        end
        
        @test length(store.data) == n
        
        # Concurrent reads
        results = Vector{String}(undef, n)
        @sync for i in 1:n
            Threads.@spawn begin
                session = get(store, i, nothing)
                results[i] = session.data
            end
        end
        
        @test all(results .== ["user-$i" for i in 1:n])
    end

end
end