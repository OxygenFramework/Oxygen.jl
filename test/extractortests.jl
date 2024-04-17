module ExtractorTests

using Base: @kwdef
using Test
using HTTP
using Suppressor
using ..Constants
using Oxygen; @oxidise
using Oxygen: extractor, Param, LazyRequest

struct Person
    name::String
    age::Int
end

@testset "JSON extractor" begin 
    req = HTTP.Request("GET", "/", [], """{"name": "joe", "age": 25}""")
    param = Param(:person, Json{Person}, missing, false)
    p = extractor(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 25
end

@testset "Partial JSON extractor" begin 
    req = HTTP.Request("GET", "/", [], """{ "person": {"name": "joe", "age": 25} }""")
    param = Param(:person, PartialJson{Person}, missing, false)
    p = extractor(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 25
end


@testset "Form extractor" begin 
    req = HTTP.Request("GET", "/", [], """name=joe&age=25""")
    param = Param(:form, Form{Person}, missing, false)
    p = extractor(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 25
end


@testset "Path extractor" begin 
    req = HTTP.Request("GET", "/person/john/20", [])
    req.context[:params] = Dict("name" => "john", "age" => "20") # simulate path params

    param = Param(:path, Path{Person}, missing, false)
    p = extractor(param, LazyRequest(request=req)).payload
    @test p.name == "john"
    @test p.age == 20
end


@testset "Query extractor" begin 
    req = HTTP.Request("GET", "/person?name=joe&age=30", [])
    param = Param(:query, Query{Person}, missing, false)
    p = extractor(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 30
end

@testset "Header extractor" begin 
    req = HTTP.Request("GET", "/person", ["name" => "joe", "age" => "19"])
    param = Param(:header, Header{Person}, missing, false)
    p = extractor(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 19
end


@testset "Body extractor" begin 

    # Parse Float64 from body
    req = HTTP.Request("GET", "/", [], "3.14")
    param = Param(:form, Body{Float64}, missing, false)
    value = extractor(param, LazyRequest(request=req)).payload
    @test value == 3.14

    # Parse String from body
    req = HTTP.Request("GET", "/", [], "Here's a regular string")
    param = Param(:form, Body{String}, missing, false)
    value = extractor(param, LazyRequest(request=req)).payload
    @test value == "Here's a regular string"
end


@kwdef struct Sample
    limit::Int
    skip::Int = 33
end

struct Parameters
    b::Int
end


@testset "Api tests" begin 

    @get "/" function(req)
        "home"
    end

    @get "/path/add/{a}/{b}" function(req, a::Int, path::Path{Parameters}, qparams::Query{Sample}, c::Nullable{Int}=23)
        return a + path.payload.b
    end

    # serve(port=PORT, async=true, show_errors=false, show_banner=false)

    r = internalrequest(HTTP.Request("GET", "/"))
    @test r.status == 200
    @test text(r) == "home"

    r = internalrequest(HTTP.Request("GET", "/path/add/3/7?limit=10"))
    @test r.status == 200
    @test text(r) == "10"

    @suppress_err begin 
        # should fail since we are missing query params
        r = internalrequest(HTTP.Request("GET", "/path/add/3/7"))
        @test r.status == 500
    end
   
end


end
