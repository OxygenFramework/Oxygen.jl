module HandlerTests
using Test
using HTTP
using ..Constants
using Oxygen; @oxidise

@get "/noarg" function(;request)
    @test isa(request, HTTP.Request)
    return text("Hello World")
end

@get "/params/double/{a}" function(req, a::Float64; request::HTTP.Request)
    @test isa(request, HTTP.Request)
    return text("$(a*2)")
end

@get "/singlearg" function(req;request)
    @test isa(req, HTTP.Request)
    @test isa(request, HTTP.Request)
    return text("Hello World")
end

serve(port=PORT, host=HOST, async=true,  show_errors=false, show_banner=false, access_log=nothing)

@testset "Handler request Injection Tests" begin

    @testset "Inject request into no arg function" begin
        response = HTTP.get("$localhost/noarg")
        @test response.status == 200
        @test text(response) == "Hello World"
    end

    @testset "Inject request into function with path params" begin
        response = HTTP.get("$localhost/params/double/5")
        @test response.status == 200
        @test text(response) == "10.0"
    end

    @testset "Inject request into function with single arg" begin
        response = HTTP.get("$localhost/singlearg")
        @test response.status == 200
        @test text(response) == "Hello World"
    end
end


terminate()

end