module ExtractorTests

using Test
using HTTP
using ..Constants
using Oxygen; @oxidise
using Oxygen: extractor, Param

struct Person
    name::String
    age::Int
end

@testset "JSON extractor" begin 
    req = HTTP.Request("GET", "/", [], """{"name": "joe", "age": 25}""")
    param = Param(:person, Json{Person}, missing, false)
    p = extractor(param, req).payload
    @test p.name == "joe"
    @test p.age == 25
end

@testset "Partial JSON extractor" begin 
    req = HTTP.Request("GET", "/", [], """{ "person": {"name": "joe", "age": 25} }""")
    param = Param(:person, PartialJson{Person}, missing, false)
    p = extractor(param, req).payload
    @test p.name == "joe"
    @test p.age == 25
end


@testset "Form extractor" begin 
    req = HTTP.Request("GET", "/", [], """name=joe&age=25""")
    param = Param(:form, Form{Person}, missing, false)
    p = extractor(param, req).payload
    @test p.name == "joe"
    @test p.age == 25
end


@testset "Path extractor" begin 
    req = HTTP.Request("GET", "/person/john/20", [])
    req.context[:params] = Dict("name" => "john", "age" => "20") # simulate path params
    param = Param(:path, Path{Person}, missing, false)
    p = extractor(param, req).payload
    @test p.name == "john"
    @test p.age == 20
end


@testset "Query extractor" begin 
    req = HTTP.Request("GET", "/person?name=joe&age=30", [])
    param = Param(:query, Query{Person}, missing, false)
    p = extractor(param, req).payload
    @test p.name == "joe"
    @test p.age == 30
end

@testset "Header extractor" begin 
    req = HTTP.Request("GET", "/person", ["name" => "joe", "age" => "19"])
    param = Param(:header, Header{Person}, missing, false)
    p = extractor(param, req).payload
    @test p.name == "joe"
    @test p.age == 19
end


@testset "Body extractor" begin 

    # Parse Float64 from body
    req = HTTP.Request("GET", "/", [], "3.14")
    param = Param(:form, Body{Float64}, missing, false)
    value = extractor(param, req).payload
    @test value == 3.14

    # Parse String from body
    req = HTTP.Request("GET", "/", [], "Here's a regular string")
    param = Param(:form, Body{String}, missing, false)
    value = extractor(param, req).payload
    @test value == "Here's a regular string"
end




end
