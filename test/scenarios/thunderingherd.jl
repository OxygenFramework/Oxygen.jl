module ThunderingHerdTest
using Test
using HTTP
using ..Constants
using Oxygen; @oxidise

allowed_origins = [ "Access-Control-Allow-Origin" => "*" ]

cors_headers = [
    allowed_origins...,
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST"
]

function CorsHandler(handle)
    return function (req::HTTP.Request)
        # return headers on OPTIONS request
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, cors_headers)
        else
            r = handle(req)
            append!(r.headers, allowed_origins)
            return r
        end
    end
end

index = router(middleware=[CorsHandler])

@get index("/") function(req)
    return "Hello World"
end

serve(
    port = PORT, 
    host = HOST, 
    async = true, 
    show_errors = false, 
    show_banner = false, 
    access_log = nothing, 
    parallel = Base.Threads.nthreads() > 1
)

@testset "async spam requests" begin

    success = 0
    failures = 0

    @sync @async for x in 1:100
        r = HTTP.request("GET", "$localhost/")
        if r.status == 200 && String(r.body) == "Hello World"
            success += 1
        else
            failures += 1
        end
    end

    @test success == 100
    @test failures == 0
end 

terminate()

end
