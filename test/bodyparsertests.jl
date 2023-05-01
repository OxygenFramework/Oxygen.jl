
module BodyParserTests 
using Test
using HTTP

include("../src/Oxygen.jl")
using .Oxygen

struct rank
    title  :: String 
    power   :: Float64
end

@testset "json() struct keyword tests" begin 

    req = HTTP.Request("GET", "/json", [], "{\"message\":[NaN,1.0]}")
    @test isnan(json(req, allow_inf = true)["message"][1])
    @test !isnan(json(req, allow_inf = true)["message"][2])

    req = HTTP.Request("GET", "/json", [], "{\"message\":[Inf,1.0]}")
    @test isinf(json(req, allow_inf = true)["message"][1])

    req = HTTP.Request("GET", "/json", [], "{\"message\":[null,1.0]}")
    @test isnothing(json(req, allow_inf = false)["message"][1])

    req = HTTP.Request("GET","/", [],"""{"title": "viscount", "power": NaN}""")
    myjson = json(req, rank, allow_inf = true)
    @test isnan(myjson.power)

    req = HTTP.Request("GET","/", [],"""{"title": "viscount", "power": 9000.1}""")
    myjson = json(req, rank, allow_inf = false)
    @test myjson.power == 9000.1

end

end