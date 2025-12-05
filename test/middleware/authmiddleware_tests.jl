module AuthMiddlewareTests

using Test
using HTTP
using Oxygen; @oxidize
using ..Constants

# Simple token validator for testing
good_token = "goodtoken"
validate_token(token) = token == good_token ? Dict(:id => 1, :name => "TestUser") : nothing

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

    # Invalid token
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Bearer badtoken"))

    # Valid token
    r = HTTP.get("$localhost/auth/protected"; headers=Dict("Authorization" => "Bearer $good_token"))
    @test r.status == 200
    @test text(r) == "Hello, TestUser!"
end

terminate()

end
