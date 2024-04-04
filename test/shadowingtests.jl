module ShadowingTests
using Test
using Oxygen; @oxidise

get("/") do 
    text("Hello World")
end

get("/add/{a}/{b}") do req, a::Int, b::Int
    text("$(a + b)")
end

@testset "Oxygen.get routing function tests" begin
    r = internalrequest(Request("GET", "/"))
    @test r.status == 200
    @test text(r) == "Hello World"
    
    r = internalrequest(Request("GET", "/add/3/7"))
    @test r.status == 200
    @test text(r) == "10"
end

@testset "Base.get dict tests" begin
    # Tests for Dictionaries
    dict = Dict("key1" => "value1", "key2" => "value2")
    @test get(dict, "key1", nothing) == "value1"
    @test get(dict, "key2", nothing) == "value2"
    @test get(dict, "key3", nothing) === nothing
end


@testset "Base.get callable tests" begin
    dict = Dict("key1" => "value1", "key2" => "value2")
    @test get(() -> "default", dict, "key1") == "value1"
    @test get(() -> "default", dict, "key3") == "default"
    @test get(() -> "another default", dict, "key4") == "another default"
    @test get(() -> 42, dict, "key5") == 42
end

@testset "Base.get callable tests with do syntax" begin
    dict = Dict("key1" => "value1", "key2" => "value2")

    @test get(dict, "key1") do
        "default"
    end == "value1"

    @test get(dict, "key2") do
        "default"
    end == "value2"

    @test get(dict, "key3") do
        "default"
    end == "default"

    @test get(dict, "key4") do
        "another default"
    end == "another default"

    @test get(dict, "key5") do
        42
    end == 42
end


@testset "Base.get tests for MyStruct" begin

    # Define a new custom struct
    struct MyStruct
        data::Dict{String, String}
    end

    # Override the Base.get method for MyStruct
    Base.get(mystruct::MyStruct, key, default) = get(mystruct.data, key, default)

    mystruct = MyStruct(Dict("key1" => "value1", "key2" => "value2"))
    @test get(mystruct, "key1", "default") == "value1"
    @test get(mystruct, "key2", "default") == "value2"
    @test get(mystruct, "key3", "default") == "default"
    
end

end