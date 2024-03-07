module BodyParserTests 
using Test
using HTTP

using Oxygen

@testset "Render Module Tests" begin

    @testset "html function" begin
        response = html("<h1>Hello, World!</h1>")
        @test response.status == 200
        @test text(response) == "<h1>Hello, World!</h1>"
        @test Dict(response.headers)["Content-Type"] == "text/html; charset=utf-8"
    end

    @testset "text function" begin
        response = text("Hello, World!")
        @test response.status == 200
        @test text(response) == "Hello, World!"
        @test Dict(response.headers)["Content-Type"] == "text/plain; charset=utf-8"
    end

    @testset "json function" begin
        response = json(Dict("message" => "Hello, World!"))
        @test response.status == 200
        @test text(response) == "{\"message\":\"Hello, World!\"}"
        @test Dict(response.headers)["Content-Type"] == "application/json; charset=utf-8"
    end

    @testset "json binary function" begin
        response = json(Vector{UInt8}("{\"message\":\"Hello, World!\"}"))
        @test response.status == 200
        @test text(response) == "{\"message\":\"Hello, World!\"}"
        @test Dict(response.headers)["Content-Type"] == "application/json; charset=utf-8"
    end
 
    @testset "xml function" begin
        response = xml("<message>Hello, World!</message>")
        @test response.status == 200
        @test text(response) == "<message>Hello, World!</message>"
        @test Dict(response.headers)["Content-Type"] == "application/xml; charset=utf-8"
    end

    @testset "js function" begin
        response = js("console.log('Hello, World!');")
        @test response.status == 200
        @test text(response) == "console.log('Hello, World!');"
        @test Dict(response.headers)["Content-Type"] == "application/javascript; charset=utf-8"
    end

    @testset "css function" begin
        response = css("body { background-color: #f0f0f0; }")
        @test response.status == 200
        @test text(response) == "body { background-color: #f0f0f0; }"
        @test Dict(response.headers)["Content-Type"] == "text/css; charset=utf-8"
    end

    @testset "binary function" begin
        response = binary(UInt8[72, 101, 108, 108, 111])  # "Hello" in ASCII
        @test response.status == 200
        @test response.body == UInt8[72, 101, 108, 108, 111]
        @test Dict(response.headers)["Content-Type"] == "application/octet-stream"
    end
end

@testset "Repeated calls do not duplicate headers" begin
    response1 = css("body { background-color: #f0f0f0; }")
    response2 = css("body { background-color: #f0f0f0; }")
    @test Dict(response1.headers)["Content-Type"] == "text/css; charset=utf-8"
    @test Dict(response2.headers)["Content-Type"] == "text/css; charset=utf-8"
    @test length(response1.headers) == length(response2.headers)

    response1 = binary(UInt8[72, 101, 108, 108, 111])  # "Hello" in ASCII
    response2 = binary(UInt8[72, 101, 108, 108, 111])  # "Hello" in ASCII
    @test Dict(response1.headers)["Content-Type"] == "application/octet-stream"
    @test Dict(response2.headers)["Content-Type"] == "application/octet-stream"
    @test length(response1.headers) == length(response2.headers) == 2
end

@testset "Repeated calls do not duplicate headers for file renderer" begin
    response1 = file("content/index.html")
    response2 = file("content/index.html")

    @test findfirst(x -> x == ("Content-Type" => "text/html; charset=utf-8"), response1.headers) !== nothing
    @test findfirst(x -> x == ("Content-Type" => "text/html; charset=utf-8"), response2.headers) !== nothing

    count1 = length(response1.headers)
    count2 = length(response2.headers)

    @test count1 == count2 == 2
end

end
