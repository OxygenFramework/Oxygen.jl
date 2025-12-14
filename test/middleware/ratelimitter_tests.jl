module RateLimiterTests

using Test
using HTTP
using Dates
using Sockets
using Oxygen; @oxidize
using ..Constants

limit = router("/limited", middleware=[RateLimiter(rate_limit=50, window_period=Second(3))])

@get limit("/goodbye", middleware=[RateLimiter(rate_limit=25, window_period=Second(3))]) function()
    return "goodbye"
end

@get limit("/greet") function()
    return "hello"
end

@get "/ok" function()
    return "ok"
end

# Create a rate limiter with realistic limits for testing (100 requests per second)
serve(middleware=[RateLimiter(rate_limit=100, window_period=Second(3))], port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

@testset "Rate Limiter Tests" begin

    # First 100 requests should succeed
    for i in 1:100
        r = HTTP.get("$localhost/ok")
        @test r.status == 200
        @test text(r) == "ok"
    end

    # 101-103rd request should be rate limited (429)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/ok"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/ok"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/ok"; retry=false)

    # Wait for the window to reset (just over 1 second)
    sleep(3.1)

    # Next 100 requests should succeed again
    for i in 1:100
        r = HTTP.get("$localhost/ok")
        @test r.status == 200
        @test text(r) == "ok"
    end

    # 101-103rd request in the new window should be rate limited again
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/ok"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/ok"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/ok"; retry=false)

end
terminate()


# Create a rate limiter with realistic limits for testing (100 requests per second)
serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)


sleep(3.1) # Ensure rate limiter window is reset before starting next testset

@testset "Limited Greet Endpoint Rate Limiter" begin
    # First 50 requests should succeed
    for i in 1:50
        r = HTTP.get("$localhost/limited/greet")
        @test r.status == 200
        @test text(r) == "hello"
    end

    # 51-53rd request should be rate limited (429)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/greet"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/greet"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/greet"; retry=false)

    # Wait for the window to reset (just over 3 seconds)
    sleep(3.1)

    # Next 50 requests should succeed again
    for i in 1:50
        r = HTTP.get("$localhost/limited/greet")
        @test r.status == 200
        @test text(r) == "hello"
    end

    # 51-53rd request in the new window should be rate limited again
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/greet"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/greet"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/greet"; retry=false)
end

sleep(3.1) # Ensure rate limiter window is reset before starting next testset

@testset "Limited Other Endpoint Rate Limiter" begin
    # First 25 requests should succeed (route-level limit)
    for i in 1:25
        r = HTTP.get("$localhost/limited/goodbye")
        @test r.status == 200
        @test text(r) == "goodbye"
    end

    # 26-28th request should be rate limited (429)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/goodbye"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/goodbye"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/goodbye"; retry=false)

    # Wait for the window to reset (just over 3 seconds)
    sleep(3.1)

    # Next 25 requests should succeed again
    for i in 1:25
        r = HTTP.get("$localhost/limited/goodbye")
        @test r.status == 200
        @test text(r) == "goodbye"
    end

    # 26-28th request in the new window should be rate limited again
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/goodbye"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/goodbye"; retry=false)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/limited/goodbye"; retry=false)
end

terminate()

rl = RateLimiter(rate_limit=1, window_period=Hour(1), cleanup_period=Second(1), cleanup_threshold=Second(1))

# Start server for background cleanup test
serve(middleware=[rl], port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

@testset "Background Cleanup Test" begin

    # First request should succeed
    r = HTTP.get("$localhost/ok"; retry=false)
    @test r.status == 200
    @test text(r) == "ok"

    # Second request should be rate limited (429)
    @test_throws HTTP.Exceptions.StatusError HTTP.get("$localhost/ok"; retry=false)

    # Wait for cleanup to run (cleanup_threshold=1s, cleanup_period=1s, wait 2.1s to ensure task runs)
    sleep(2.1)

    # Third request should succeed because the IP entry was cleaned up
    r = HTTP.get("$localhost/ok"; retry=false)
    @test r.status == 200
    @test text(r) == "ok"
end

terminate()

end