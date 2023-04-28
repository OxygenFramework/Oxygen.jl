
module BodyParserTests 
using Test
using HTTP

include("../src/Oxygen.jl")
using .Oxygen

@testset "json() struct keyword tests" begin 

    req = HTTP.Request("GET", "/json", [], "{\"message\":[NaN,1.0]}")
    @test isnan(json(req, allow_inf = true)["message"][1])
    @test !isnan(json(req, allow_inf = true)["message"][2])

    req = HTTP.Request("GET", "/json", [], "{\"message\":[Inf,1.0]}")
    @test isinf(json(req, allow_inf = true)["message"][1])

    req = HTTP.Request("GET", "/json", [], "{\"message\":[null,1.0]}")
    @test isnothing(json(req, allow_inf = false)["message"][1])

end

end