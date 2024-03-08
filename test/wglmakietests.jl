module CairoMakieTests
using HTTP
using Test
using Bonito
using WGLMakie: heatmap
using Oxygen; @oxidise
import Oxygen: text, html
using ..Constants

@testset "WGLMakie Utils tests" begin 
    # create a random heatmap
    fig = heatmap(rand(50, 50))

    response = html(fig)
    @test response isa HTTP.Response
    @test response.status == 200
    @test HTTP.header(response, "Content-Type") == "text/html"
    @test parse(Int, HTTP.header(response, "Content-Length")) >= 0
end

@testset "WGLMakie server tests" begin

    get("/") do 
        text("hello world")
    end

    get("/html") do 
        html("hello world")
    end

    # generate a random plot
    get("/plot/html") do 
        fig = heatmap(rand(50, 50))
        html(fig)
    end

    serve(host=HOST, port=PORT, async=true, show_banner=false, access_log=nothing)

    # Test overloaded text() function
    r = HTTP.get("$localhost/")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/plain; charset=utf-8"
    @test parse(Int, HTTP.header(r, "Content-Length")) >= 0

    # Test overloaded html function
    r = HTTP.get("$localhost/html")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/html; charset=utf-8"
    @test parse(Int, HTTP.header(r, "Content-Length")) >= 0

    # Test for /plot/html endpoint
    r = HTTP.get("$localhost/plot/html")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/html"
    @test parse(Int, HTTP.header(r, "Content-Length")) >= 0
    terminate()
end

end