
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
    end

    @testset "text function" begin
        renderer = text("Hello, World!")
        @test renderer.response.status == 200
        @test text(renderer.response) == "Hello, World!"
    end

    @testset "json function" begin
        renderer = json(Dict("message" => "Hello, World!"))
        @test renderer.response.status == 200
        @test text(renderer.response) == "{\"message\":\"Hello, World!\"}"
    end

    @testset "xml function" begin
        renderer = xml("<message>Hello, World!</message>")
        @test renderer.response.status == 200
        @test text(renderer.response) == "<message>Hello, World!</message>"
    end

    @testset "js function" begin
        renderer = js("console.log('Hello, World!');")
        @test renderer.response.status == 200
        @test text(renderer.response) == "console.log('Hello, World!');"
    end

    @testset "css function" begin
        renderer = css("body { background-color: #f0f0f0; }")
        @test renderer.response.status == 200
        @test text(renderer.response) == "body { background-color: #f0f0f0; }"
    end

    @testset "binary function" begin
        renderer = binary(UInt8[72, 101, 108, 108, 111])  # "Hello" in ASCII
        @test renderer.response.status == 200
        @test renderer.response.body == UInt8[72, 101, 108, 108, 111]
    end
end






end