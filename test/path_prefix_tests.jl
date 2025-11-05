module PathPrefixUrlTests

using Test
using HTTP
using ..Constants
using Oxygen; @oxidise

@get "/test" function()
    return "Hello World"
end

serve(prefix="/custom-api", port=PORT, host=HOST, async=true,  show_errors=false, show_banner=false)

@testset "Valid Prefixed requests" begin 
    r = internalrequest(HTTP.Request("GET", "/custom-api/test"))
    @test r.status == 200
    @test text(r) == "Hello World"

    r = internalrequest(HTTP.Request("GET", "/custom-api/docs"))
    @test r.status == 200

    r = internalrequest(HTTP.Request("GET", "/custom-api/docs/schema"))
    @test r.status == 200

    r = internalrequest(HTTP.Request("GET", "/custom-api/docs/metrics"))
    @test r.status == 200

end


# 404 related tests (direct hits which shouldn't work)
@testset "Invalid Non-Prefixed requests" begin 

    r = internalrequest(HTTP.Request("GET", "/test"))
    @test r.status == 404

    r = internalrequest(HTTP.Request("GET", "/docs"))
    @test r.status == 404

    r = internalrequest(HTTP.Request("GET", "/docs/schema"))
    @test r.status == 404

    r = internalrequest(HTTP.Request("GET", "/docs/metrics"))
    @test r.status == 404

end

terminate()

end