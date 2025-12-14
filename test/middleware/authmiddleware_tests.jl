module AuthMiddlewareTests

using Test
using HTTP
using Oxygen; @oxidize
using ..Constants

good_token = "goodtoken"
validate_token(token) = token == good_token ? Dict(:id => 1, :name => "TestUser") : nothing

@testset "BearerAuth unit tests (direct middleware calls)" begin
    # Build middleware around a simple handler that returns 200
    mw = BearerAuth(validate_token)
    handler = mw(req->HTTP.Response(200, "ok"))

    # Case A: header == "Bearer " (exactly the scheme + single space) -> header_len == scheme_prefix_len -> invalid
    reqA = HTTP.Request("GET", "/")
    HTTP.setheader(reqA, "Authorization" => "Bearer ")
    resA = handler(reqA)
    @test isa(resA, HTTP.Response)
    @test resA.status == 401

    # Case B: header == "Bearer  " (scheme + two spaces) -> token portion is whitespace, stripped to empty -> invalid
    reqB = HTTP.Request("GET", "/")
    HTTP.setheader(reqB, "Authorization" => "Bearer  ")
    resB = handler(reqB)
    @test isa(resB, HTTP.Response)
    @test resB.status == 401

    # Case C: valid token but invalid (validator returns nothing) -> EXPIRED_TOKEN (401)
    reqC = HTTP.Request("GET", "/")
    HTTP.setheader(reqC, "Authorization" => "Bearer badtoken")
    resC = handler(reqC)
    @test isa(resC, HTTP.Response)
    @test resC.status == 401

    # Case D: valid token -> handler should be invoked and return 200
    reqD = HTTP.Request("GET", "/")
    HTTP.setheader(reqD, "Authorization" => "Bearer $good_token")
    resD = handler(reqD)
    @test isa(resD, HTTP.Response)
    @test resD.status == 200
    @test text(resD) == "ok"
end


# Set up router with AuthMiddleware
auth = router("/auth", middleware=[BearerAuth(validate_token)])

@get auth("/protected") function(req)
    # Return user info from context
    user = req.context[:user]
    return HTTP.Response(200, "Hello, $(user[:name])!")
end

# Start server for tests
serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

@testset "BearerAuth Middleware Tests" begin

    # No Authorization header
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/auth/protected")

    # Malformed header (wrong scheme)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Basic abcdef"))

    # Malformed header (empty token)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Bearer "))

    # Malformed header (passes length check but token is whitespace -> stripped to empty)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Bearer  "))

    # Malformed header (no trailing space - wrong format)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Bearer"))

    # Invalid token
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Bearer badtoken"))

    # Valid token
    r = HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Bearer $good_token"))
    @test r.status == 200
    @test text(r) == "Hello, TestUser!"
end

terminate()


end
