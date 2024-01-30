module BodyParserTests 
using Test
using HTTP

include("../src/Oxygen.jl")
using .Oxygen

@testset "Render Module Tests" begin

    @testset "html function" begin
        renderer = html("<h1>Hello, World!</h1>")
        @test renderer.response.status == 200
        @test text(renderer.response) == "<h1>Hello, World!</h1>"
        @test Dict(renderer.response.headers)["Content-Type"] == "text/html; charset=utf-8"
    end

    @testset "text function" begin
        renderer = text("Hello, World!")
        @test renderer.response.status == 200
        @test text(renderer.response) == "Hello, World!"
        @test Dict(renderer.response.headers)["Content-Type"] == "text/plain; charset=utf-8"
    end

    @testset "json function" begin
        renderer = json(Dict("message" => "Hello, World!"))
        @test renderer.response.status == 200
        @test text(renderer.response) == "{\"message\":\"Hello, World!\"}"
        @test Dict(renderer.response.headers)["Content-Type"] == "application/json; charset=utf-8"
    end

    @testset "xml function" begin
        renderer = xml("<message>Hello, World!</message>")
        @test renderer.response.status == 200
        @test text(renderer.response) == "<message>Hello, World!</message>"
        @test Dict(renderer.response.headers)["Content-Type"] == "application/xml; charset=utf-8"
    end

    @testset "js function" begin
        renderer = js("console.log('Hello, World!');")
        @test renderer.response.status == 200
        @test text(renderer.response) == "console.log('Hello, World!');"
        @test Dict(renderer.response.headers)["Content-Type"] == "application/javascript; charset=utf-8"
    end

    @testset "css function" begin
        renderer = css("body { background-color: #f0f0f0; }")
        @test renderer.response.status == 200
        @test text(renderer.response) == "body { background-color: #f0f0f0; }"
        @test Dict(renderer.response.headers)["Content-Type"] == "text/css; charset=utf-8"
    end

    @testset "binary function" begin
        renderer = binary(UInt8[72, 101, 108, 108, 111])  # "Hello" in ASCII
        @test renderer.response.status == 200
        @test renderer.response.body == UInt8[72, 101, 108, 108, 111]
        @test Dict(renderer.response.headers)["Content-Type"] == "application/octet-stream"
    end
end

end