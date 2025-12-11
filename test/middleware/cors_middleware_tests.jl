module CORSMiddlewareTests

module RouterLevelTests 

    using Test
    using HTTP
    using Oxygen; @oxidize
    using ...Constants

    # Set up router with CORS middleware (default config)
    cors_router = router("/cors", middleware=[Cors()])
    @route ["GET", "OPTIONS"] cors_router("/hello") function()
        return "ok"
    end

    # Custom config: allow_credentials and max_age
    custom_router = router("/customcors", middleware=[Cors(allowed_origins=["https://example.com"], allow_credentials=true, max_age=600)])
    @route ["GET", "OPTIONS"] custom_router("/test") function() 
        return "custom" 
    end

    # Start server for tests

    custom_header_router = router("/extracors", middleware=[Cors(extra_headers=["Access-Control-Expose-Headers" => "X-My-Header", "X-Test-Header" => "TestValue"])])
    @route ["GET", "OPTIONS"] custom_header_router("/custom") function()
        return "custom headers"
    end

    serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

    @testset "CORS Middleware Tests" begin
        # Preflight OPTIONS request
        r = HTTP.request("OPTIONS", "$localhost/cors/hello")
        @test r.status == 200
        @test HTTP.header(r, "Access-Control-Allow-Origin") == "*"
        @test HTTP.header(r, "Access-Control-Allow-Headers") == "*"
        @test occursin("GET", HTTP.header(r, "Access-Control-Allow-Methods"))
        @test occursin("POST", HTTP.header(r, "Access-Control-Allow-Methods"))
        @test occursin("OPTIONS", HTTP.header(r, "Access-Control-Allow-Methods"))

        # GET request includes CORS headers
        r = HTTP.get("$localhost/cors/hello")
        @test r.status == 200
        @test HTTP.header(r, "Access-Control-Allow-Origin") == "*"
        @test HTTP.header(r, "Access-Control-Allow-Headers") == "*"
        @test occursin("GET", HTTP.header(r, "Access-Control-Allow-Methods"))

        r = HTTP.request("OPTIONS", "$localhost/customcors/test")
        @test HTTP.header(r, "Access-Control-Allow-Origin") == "https://example.com"
        @test HTTP.header(r, "Access-Control-Allow-Credentials") == "true"
        @test HTTP.header(r, "Access-Control-Max-Age") == "600"

        # Custom CORS headers test
        r = HTTP.request("OPTIONS", "$localhost/extracors/custom")
        @test HTTP.header(r, "Access-Control-Expose-Headers") == "X-My-Header"
        @test HTTP.header(r, "X-Test-Header") == "TestValue"

        r = HTTP.get("$localhost/extracors/custom")
        @test HTTP.header(r, "Access-Control-Expose-Headers") == "X-My-Header"
        @test HTTP.header(r, "X-Test-Header") == "TestValue"
    end

    terminate()

end


module GlobalCorsTests

    using Test
    using HTTP
    using Oxygen; @oxidize
    using ...Constants

    @get "/hello" function()
        return "ok"
    end

    serve(middleware=[Cors()], port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

    # Preflight OPTIONS request
    r = HTTP.request("OPTIONS", "$localhost/hello")
    @test r.status == 200
    @test HTTP.header(r, "Access-Control-Allow-Origin") == "*"
    @test HTTP.header(r, "Access-Control-Allow-Headers") == "*"
    @test occursin("GET", HTTP.header(r, "Access-Control-Allow-Methods"))
    @test occursin("POST", HTTP.header(r, "Access-Control-Allow-Methods"))
    @test occursin("OPTIONS", HTTP.header(r, "Access-Control-Allow-Methods"))

    terminate()
end

end
