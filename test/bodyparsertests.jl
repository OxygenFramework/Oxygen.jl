
module BodyParserTests 
using Test
using HTTP
using StructTypes

include("../src/Oxygen.jl")
using .Oxygen

struct rank
    title   :: String 
    power   :: Float64
end

# added supporting structype
StructTypes.StructType(::Type{rank}) = StructTypes.Struct()

req = HTTP.Request("GET", "/json", [], """{"message":["hello",1.0]}""")
json(req)

@testset "formdata() Request struct keyword tests" begin 
    req = HTTP.Request("POST", "/", [], "message=hello world&value=3")
    data = formdata(req)
    @test data["message"] == "hello world"
    @test data["value"] == "3"
end

@testset "formdata() Response struct keyword tests" begin 
    req = HTTP.Response("message=hello world&value=3")
    data = formdata(req)
    @test data["message"] == "hello world"
    @test data["value"] == "3"
end


@testset "json() Request struct keyword tests" begin 


    @testset "json() Request struct keyword tests" begin 

        req = HTTP.Request("GET", "/json", [], "{\"message\":[NaN,1.0]}")
        @test isnan(json(req, allow_inf = true)["message"][1])
        @test !isnan(json(req, allow_inf = true)["message"][2])

        req = HTTP.Request("GET", "/json", [], "{\"message\":[Inf,1.0]}")
        @test isinf(json(req, allow_inf = true)["message"][1])

        req = HTTP.Request("GET", "/json", [], "{\"message\":[null,1.0]}")
        @test isnothing(json(req, allow_inf = false)["message"][1])

    end


    @testset "json() Request stuct keyword with classtype" begin 

        req = HTTP.Request("GET","/", [],"""{"title": "viscount", "power": NaN}""")
        myjson = json(req, rank, allow_inf = true)
        @test isnan(myjson.power)

        req = HTTP.Request("GET","/", [],"""{"title": "viscount", "power": 9000.1}""")
        myjson = json(req, rank, allow_inf = false)
        @test myjson.power == 9000.1

    end


    @testset "regular Request json() tests" begin 

        req = HTTP.Request("GET", "/json", [], "{\"message\":[null,1.0]}")
        @test isnothing(json(req)["message"][1])
        @test json(req)["message"][2] == 1

        req = HTTP.Request("GET", "/json", [], """{"message":["hello",1.0]}""")
        @test json(req)["message"][1] == "hello"
        @test json(req)["message"][2] == 1

        req = HTTP.Request("GET", "/json", [], "{\"message\":[3.4,4.0]}")
        @test json(req)["message"][1] == 3.4
        @test json(req)["message"][2] == 4

        req = HTTP.Request("GET", "/json", [], "{\"message\":[null,1.0]}")
        @test isnothing(json(req)["message"][1])
    end


    @testset "json() Request with classtype" begin 

        req = HTTP.Request("GET","/", [],"""{"title": "viscount", "power": NaN}""")
        myjson = json(req, rank)
        @test isnan(myjson.power)

        req = HTTP.Request("GET","/", [],"""{"title": "viscount", "power": 9000.1}""")
        myjson = json(req, rank)
        @test myjson.power == 9000.1

        # test invalid json
        req = HTTP.Request("GET","/", [],"""{}""")
        @test_throws MethodError json(req, rank) 

        # test extra key
        req = HTTP.Request("GET","/", [],"""{"title": "viscount", "power": 9000.1, "extra": "hi"}""")
        myjson = json(req, rank)
        @test myjson.power == 9000.1

    end


    @testset "json() Response" begin 

        res = HTTP.Response("""{"title": "viscount", "power": 9000.1}""")
        myjson = json(res)
        @test myjson["power"] == 9000.1

        res = HTTP.Response("""{"title": "viscount", "power": 9000.1}""")
        myjson = json(res, rank)
        @test myjson.power == 9000.1

    end

    @testset "json() Response struct keyword tests" begin 

        req = HTTP.Response("{\"message\":[NaN,1.0]}")
        @test isnan(json(req, allow_inf = true)["message"][1])
        @test !isnan(json(req, allow_inf = true)["message"][2])

        req = HTTP.Response("{\"message\":[Inf,1.0]}")
        @test isinf(json(req, allow_inf = true)["message"][1])

        req = HTTP.Response("{\"message\":[null,1.0]}")
        @test isnothing(json(req, allow_inf = false)["message"][1])

    end


    @testset "json() Response stuct keyword with classtype" begin 

        req = HTTP.Response("""{"title": "viscount", "power": NaN}""")
        myjson = json(req, rank, allow_inf = true)
        @test isnan(myjson.power)

        req = HTTP.Response("""{"title": "viscount", "power": 9000.1}""")
        myjson = json(req, rank, allow_inf = false)
        @test myjson.power == 9000.1

    end


    @testset "regular json() Response tests" begin 

        req = HTTP.Response("{\"message\":[null,1.0]}")
        @test isnothing(json(req)["message"][1])
        @test json(req)["message"][2] == 1

        req = HTTP.Response("""{"message":["hello",1.0]}""")
        @test json(req)["message"][1] == "hello"
        @test json(req)["message"][2] == 1

        req = HTTP.Response("{\"message\":[3.4,4.0]}")
        @test json(req)["message"][1] == 3.4
        @test json(req)["message"][2] == 4

        req = HTTP.Response("{\"message\":[null,1.0]}")
        @test isnothing(json(req)["message"][1])
    end


    @testset "json() Response with classtype" begin 

        req = HTTP.Response("""{"title": "viscount", "power": NaN}""")
        myjson = json(req, rank)
        @test isnan(myjson.power)

        req = HTTP.Response("""{"title": "viscount", "power": 9000.1}""")
        myjson = json(req, rank)
        @test myjson.power == 9000.1

        # test invalid json
        req = HTTP.Response("""{}""")
        @test_throws MethodError json(req, rank) 

        # test extra key
        req = HTTP.Response("""{"title": "viscount", "power": 9000.1, "extra": "hi"}""")
        myjson = json(req, rank)
        @test myjson.power == 9000.1

    end


    end

end