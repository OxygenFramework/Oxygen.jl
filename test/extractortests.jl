module ExtractorTests

using Base: @kwdef
using Test
using HTTP
using Suppressor
using ProtoBuf
using ..Constants
using Oxygen; @oxidise
using Oxygen: extract, Param, LazyRequest, Extractor, ProtoBuffer, isbodyparam

# extend the built-in validate function
import Oxygen: validate

include("extensions/protobuf/messages/test_pb.jl")
using .test_pb: MyMessage 

struct Person
    name::String
    age::Int
end

@kwdef struct Home
    address::String
    owner::Person
end

# Add a lower bound to age with a global validator
validate(p::Person) = p.age >= 0

@testset "Extactor builder sytnax" begin 

    @test Json{Person}(x -> x.age >= 25) isa Extractor

    @test Json(Person) isa Extractor
    @test Json(Person, x -> x.age >= 25) isa Extractor

    p = Person("joe", 25)

    @test Json(p) isa Extractor
    @test Json(p, x -> x.age >= 25) isa Extractor
end

@testset "JSON extract" begin 
    req = HTTP.Request("GET", "/", [], """{"name": "joe", "age": 25}""")
    param = Param(:person, Json{Person}, missing, false)
    p = extract(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 25
end

@testset "kwarg_struct_builder Nested test" begin 
    req = HTTP.Request("GET", "/", [], """
    {
        "address": "123 main street",
        "owner": {
            "name": "joe",
            "age": 25
        }
    }
    """)
    param = Param(:person, Json{Home}, missing, false)
    p = extract(param, LazyRequest(request=req)).payload
    @test p isa Home
    @test p.owner isa Person
    @test p.address == "123 main street"
    @test p.owner.name == "joe"
    @test p.owner.age == 25
end

@testset "isbodyparam tests" begin 
    param = Param(:person, Json{Home}, missing, false)
    @test isbodyparam(param) == true
end

@testset "Partial JSON extract" begin 
    req = HTTP.Request("GET", "/", [], """{ "person": {"name": "joe", "age": 25} }""")
    param = Param(:person, JsonFragment{Person}, missing, false)
    p = extract(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 25
end


@testset "Form extract" begin 
    req = HTTP.Request("GET", "/", [], """name=joe&age=25""")
    param = Param(:form, Form{Person}, missing, false)
    p = extract(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 25


    # Test that negative age trips the global validator
    req = HTTP.Request("GET", "/", [], """name=joe&age=-4""")
    param = Param(:form, Form{Person}, missing, false)
    @test_throws Oxygen.Core.Errors.ValidationError extract(param, LazyRequest(request=req))


    # Test that age < 25 trips the local validator
    req = HTTP.Request("GET", "/", [], """name=joe&age=10""")
    default_value = Form{Person}(x -> x.age > 25)
    param = Param(:form, Form{Person}, default_value, true)
    @test_throws Oxygen.Core.Errors.ValidationError extract(param, LazyRequest(request=req))
end


@testset "Path extract" begin 
    req = HTTP.Request("GET", "/person/john/20", [])
    req.context[:params] = Dict("name" => "john", "age" => "20") # simulate path params

    param = Param(:path, Path{Person}, missing, false)
    p = extract(param, LazyRequest(request=req)).payload
    @test p.name == "john"
    @test p.age == 20
end


@testset "Query extract" begin 
    req = HTTP.Request("GET", "/person?name=joe&age=30", [])
    param = Param(:query, Query{Person}, missing, false)
    p = extract(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 30

    # test custom instance validator
    req = HTTP.Request("GET", "/person?name=joe&age=30", [])
    default_value = Query{Person}(x -> x.age > 25)
    param = Param(:query, Query{Person}, default_value, true)
    p = extract(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 30
end

@testset "Header extract" begin 
    req = HTTP.Request("GET", "/person", ["name" => "joe", "age" => "19"])
    param = Param(:header, Header{Person}, missing, false)
    p = extract(param, LazyRequest(request=req)).payload
    @test p.name == "joe"
    @test p.age == 19
end


@testset "Body extract" begin 

    # Parse Float64 from body
    req = HTTP.Request("GET", "/", [], "3.14")
    param = Param(:form, Body{Float64}, missing, false)
    value = extract(param, LazyRequest(request=req)).payload
    @test value == 3.14

    # Parse String from body
    req = HTTP.Request("GET", "/", [], "Here's a regular string")
    param = Param(:form, Body{String}, missing, false)
    value = extract(param, LazyRequest(request=req)).payload
    @test value == "Here's a regular string"
end


@kwdef struct Sample
    limit::Int
    skip::Int = 33
end

@kwdef struct PersonWithDefault
    name::String
    age::Int
    value::Float64 = 1.5
end

struct Parameters
    b::Int
end

@testset "Api tests" begin 

    get("/") do 
        text("home")
    end

    @get "/headers" function(req, headers = Header(Sample, s -> s.limit > 5))
        return headers.payload
    end

    post("/form") do req, form::Form{Sample}
        return form.payload |> json
    end

    get("/query") do req, query::Query{Sample}
        return query.payload |> json
    end

    post("/body/string") do req, body::Body{String}
        return body.payload
    end

    post("/body/float") do req, body::Body{Float64}
        return body.payload
    end

    @post "/json" function(req, data = Json{PersonWithDefault}(s -> s.value < 10))
        return data.payload
    end
 
    post("/protobuf") do req, data::ProtoBuffer{MyMessage}
        return  protobuf(data.payload)
    end

    post("/json/partial") do req, p1::JsonFragment{PersonWithDefault}, p2::JsonFragment{PersonWithDefault}
        return json((p1=p1.payload, p2=p2.payload))
    end

    @get "/path/add/{a}/{b}" function(req, a::Int, path::Path{Parameters}, qparams::Query{Sample}, c::Nullable{Int}=23)
        return a + path.payload.b
    end

    r = internalrequest(HTTP.Request("GET", "/"))
    @test r.status == 200
    @test text(r) == "home"

    r = internalrequest(HTTP.Request("GET", "/path/add/3/7?limit=10"))
    @test r.status == 200
    @test text(r) == "10"

    r = internalrequest(HTTP.Request("POST", "/form", [], """limit=10&skip=25"""))
    @test r.status == 200
    data = json(r)
    @test data["limit"] == 10
    @test data["skip"] == 25

    r = internalrequest(HTTP.Request("GET", "/query?limit=10&skip=25"))
    @test r.status == 200
    data = json(r)
    @test data["limit"] == 10
    @test data["skip"] == 25
    
    r = internalrequest(HTTP.Request("POST", "/body/string", [], """Hello World!"""))
    @test r.status == 200
    @test text(r) == "Hello World!"

    r = internalrequest(HTTP.Request("POST", "/body/float", [], """3.14"""))
    @test r.status == 200
    @test parse(Float64, text(r)) == 3.14

    @suppress_err begin 
        # should fail since we are missing query params
        r = internalrequest(HTTP.Request("GET", "/path/add/3/7"))
        @test r.status == 400
    end

    r = internalrequest(HTTP.Request("GET", "/headers", ["limit" => "10"], ""))
    @test r.status == 200
    data = json(r)
    @test data["limit"] == 10
    @test data["skip"] == 33

    @suppress_err begin 
        # should fail since we are missing query params
        r = internalrequest(HTTP.Request("GET", "/headers", ["limit" => "3"], ""))
        @test r.status == 400
    end

    @suppress_err begin 
        # value is higher than the limit set in the validator
        r = internalrequest(HTTP.Request("POST", "/json", [], """
        {
            "name": "joe",
            "age": 24,
            "value": 12.0
        }
        """))
        @test r.status == 400
    end

    r = internalrequest(HTTP.Request("POST", "/json", [], """
    {
        "name": "joe",
        "age": 24,
        "value": 4.8
    }
    """))
    data = json(r)
    @test data["name"] == "joe"
    @test data["age"] == 24
    @test data["value"] == 4.8

    r = internalrequest(HTTP.Request("POST", "/json/partial", [], """
    {
        "p1": {
            "name": "joe",
            "age": "24"
        },
        "p2": {
            "name": "kim",
            "age": "25",
            "value": 100.0
        }
    }
    """))

    @test r.status == 200
    data = json(r)
    p1 = data["p1"]
    p2 = data["p2"]

    @test p1["name"] == "joe"
    @test p1["age"] == 24
    @test p1["value"] == 1.5

    @test p2["name"] == "kim"
    @test p2["age"] == 25
    @test p2["value"] == 100

    message = MyMessage(-1, ["a", "b"])
    r = internalrequest(protobuf(message, "/protobuf"))
    decoded_msg = protobuf(r, MyMessage)

    @test decoded_msg isa MyMessage
    @test decoded_msg.a == -1
    @test decoded_msg.b == ["a", "b"]

end


end
