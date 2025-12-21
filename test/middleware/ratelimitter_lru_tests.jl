module RateLimiterLRUTests

using Test
using HTTP
using Dates
using Sockets
using Oxygen; @oxidize
using ..Constants

limit = router("/limited", middleware=[RateLimiter(strategy=:sliding_window, rate_limit=50, window=Second(3))])

@get limit("/goodbye", middleware=[RateLimiter(strategy=:sliding_window, rate_limit=25, window=Second(3))]) function()
    return "goodbye"
end

@get limit("/greet") function()
    return "hello"
end

@get "/ok" function()
    return "ok"
end

# Create a rate limiter with realistic limits for testing (100 requests per second)
serve(middleware=[RateLimiter(strategy=:sliding_window, rate_limit=100, window=Second(3))], port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

@testset "Rate Limiter Tests" begin

    # First 100 requests should succeed with decreasing remaining count
    for i in 1:100
        r = HTTP.get("$localhost/ok")
        @test r.status == 200
        @test text(r) == "ok"
        @test HTTP.header(r, "X-RateLimit-Limit") == "100"
        @test HTTP.header(r, "X-RateLimit-Remaining") == string(100 - i)
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3  # Should be within window period
    end

    # 101-103rd request should be rate limited (429) with proper headers
    for i in 1:3
        try
            HTTP.get("$localhost/ok"; retry=false)
            @test false  # Should not reach here
        catch e
            @test e isa HTTP.Exceptions.StatusError
            @test e.response.status == 429
            @test HTTP.header(e.response, "X-RateLimit-Limit") == "100"
            @test HTTP.header(e.response, "X-RateLimit-Remaining") == "0"
            reset_time = parse(Int, HTTP.header(e.response, "X-RateLimit-Reset"))
            @test reset_time > 0 && reset_time <= 3
        end
    end

    # Wait for the window to reset (just over 3 seconds)
    sleep(3.1)

    # Next 100 requests should succeed again with decreasing remaining count
    for i in 1:100
        r = HTTP.get("$localhost/ok")
        @test r.status == 200
        @test text(r) == "ok"
        @test HTTP.header(r, "X-RateLimit-Limit") == "100"
        @test HTTP.header(r, "X-RateLimit-Remaining") == string(100 - i)
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3
    end

    # 101-103rd request in the new window should be rate limited again
    for i in 1:3
        try
            HTTP.get("$localhost/ok"; retry=false)
            @test false
        catch e
            @test e isa HTTP.Exceptions.StatusError
            @test e.response.status == 429
            @test HTTP.header(e.response, "X-RateLimit-Limit") == "100"
            @test HTTP.header(e.response, "X-RateLimit-Remaining") == "0"
            reset_time = parse(Int, HTTP.header(e.response, "X-RateLimit-Reset"))
            @test reset_time > 0 && reset_time <= 3
        end
    end

end
terminate()


# Create a server without global middleware but with route-level middleware on /limited/*
serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)


sleep(5) # Ensure rate limiter window is completely reset and any background cleanup is done

@testset "Limited Greet Endpoint Rate Limiter" begin
    # First 50 requests should succeed with decreasing remaining count
    for i in 1:50
        r = HTTP.get("$localhost/limited/greet")
        @test r.status == 200
        @test text(r) == "hello"
        @test HTTP.header(r, "X-RateLimit-Limit") == "50"
        @test HTTP.header(r, "X-RateLimit-Remaining") == string(50 - i)
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3
    end

    # 51-53rd request should be rate limited (429)
    for i in 1:3
        try
            HTTP.get("$localhost/limited/greet"; retry=false)
            @test false
        catch e
            @test e isa HTTP.Exceptions.StatusError
            @test e.response.status == 429
            @test HTTP.header(e.response, "X-RateLimit-Limit") == "50"
            @test HTTP.header(e.response, "X-RateLimit-Remaining") == "0"
            reset_time = parse(Int, HTTP.header(e.response, "X-RateLimit-Reset"))
            @test reset_time > 0 && reset_time <= 3
        end
    end

    # Wait for the window to reset (just over 3 seconds)
    sleep(3.1)

    # Next 50 requests should succeed again
    for i in 1:50
        r = HTTP.get("$localhost/limited/greet")
        @test r.status == 200
        @test text(r) == "hello"
        @test HTTP.header(r, "X-RateLimit-Limit") == "50"
        @test HTTP.header(r, "X-RateLimit-Remaining") == string(50 - i)
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3
    end

    # 51-53rd request in the new window should be rate limited again
    for i in 1:3
        try
            HTTP.get("$localhost/limited/greet"; retry=false)
            @test false
        catch e
            @test e isa HTTP.Exceptions.StatusError
            @test e.response.status == 429
            @test HTTP.header(e.response, "X-RateLimit-Limit") == "50"
            @test HTTP.header(e.response, "X-RateLimit-Remaining") == "0"
            reset_time = parse(Int, HTTP.header(e.response, "X-RateLimit-Reset"))
            @test reset_time > 0 && reset_time <= 3
        end
    end
end

sleep(3.1) # Ensure rate limiter window is reset before starting next testset

@testset "Limited Other Endpoint Rate Limiter" begin
    # First 25 requests should succeed (route-level limit enforced, headers show route-level limit)
    for i in 1:25
        r = HTTP.request("GET", "$localhost/limited/goodbye", status_exception=false)
        @test r.status == 200
        @test text(r) == "goodbye"
        @test HTTP.header(r, "X-RateLimit-Limit") == "25"  # Headers set by route-level middleware
        @test HTTP.header(r, "X-RateLimit-Remaining") == string(25 - i)
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3
    end

    # 26-28th request should be rate limited (429) - route-level limit enforced
    for i in 1:3
        r = HTTP.request("GET", "$localhost/limited/goodbye", status_exception=false)
        @test r.status == 429
        @test HTTP.header(r, "X-RateLimit-Limit") == "25"  # Headers show route-level
        @test HTTP.header(r, "X-RateLimit-Remaining") == "0"
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3
    end

    # Wait for the window to reset (just over 3 seconds)
    sleep(3.1)

    # Next 25 requests should succeed again after reset
    for i in 1:25
        r = HTTP.request("GET", "$localhost/limited/goodbye", status_exception=false)
        @test r.status == 200
        @test text(r) == "goodbye"
        @test HTTP.header(r, "X-RateLimit-Limit") == "25"
        @test HTTP.header(r, "X-RateLimit-Remaining") == string(25 - i)
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3
    end

    # 26-28th request in the new window should be rate limited again
    for i in 1:3
        r = HTTP.request("GET", "$localhost/limited/goodbye", status_exception=false)
        @test r.status == 429
        @test HTTP.header(r, "X-RateLimit-Limit") == "25"
        @test HTTP.header(r, "X-RateLimit-Remaining") == "0"
        reset_time = parse(Int, HTTP.header(r, "X-RateLimit-Reset"))
        @test reset_time > 0 && reset_time <= 3
    end
end

terminate()

end