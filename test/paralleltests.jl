module ParallelTests

using Test
using HTTP
using Suppressor
using Oxygen; @oxidise

using ..Constants

@testset "parallel tests" begin 

    invocation = []

    function handler1(handler)
        return function(req::HTTP.Request)
            push!(invocation, 1)
            handler(req)
        end
    end

    function handler2(handler)
        return function(req::HTTP.Request)
            push!(invocation, 2)
            handler(req)
        end
    end

    function handler3(handler)
        return function(req::HTTP.Request)
            push!(invocation, 3)
            handler(req)
        end
    end

    get("/get") do
        return "Hello World"
    end

    post("/post") do req::Request
        return text(req)
    end

    @get("/customerror") do
        function processtring(input::String)
            "<$input>"
        end
        processtring(3)
    end

    if Threads.nthreads() <= 1
        # the service should work even when we only have a single thread available (not ideal)
        @async serveparallel(port=PORT, show_errors=false, show_banner=false, queuesize=100)
        r = HTTP.get("$localhost/get")
        @test r.status == 200

        # clean up the server on tests without additional threads
        terminate()
    end

    # only run these tests if we have more than one thread to work with
    if Threads.nthreads() > 1

        serveparallel(host=HOST, port=PORT, show_errors=true, async=true, show_banner=true)
        sleep(3)

        r = HTTP.get("$localhost/get")
        @test r.status == 200

        r = HTTP.post("$localhost/post", body="some demo content")
        @test text(r) == "some demo content"

        try
            @suppress_err r = HTTP.get("$localhost/customerror", connect_timeout=3)
        catch e 
            @test e isa MethodError || e isa HTTP.ExceptionRequest.StatusError
        end
        
        terminate()

        serveparallel(host=HOST, port=PORT, middleware=[handler1, handler2, handler3], show_errors=true, async=true, show_banner=false)
        sleep(1)

        r = HTTP.get("$localhost/get")
        @test r.status == 200

        terminate()
    end

end
end