module ReflectionTests

using Test
using Base: @kwdef
using Oxygen: splitdef, Json
using Oxygen.Core.Reflection: getsignames, parsetype, kwarg_struct_builder, parse_array_value


global message = Dict("message" => "Hello, World!")

struct Person
    name::String
    age::Int
end

@enum Fruit apple = 1 banana = 2

@kwdef struct Home
    address::String
    owner::Person
end

@kwdef struct Company
    name::String
    employees::Vector{Person} = Person[]
    revenues::Vector{Int} = Int[]
end

@kwdef struct Roster
    members::Vector{Union{Person, Nothing}} = Union{Person, Nothing}[]
end


function getinfo(f::Function)
    return splitdef(f)
end

@testset "getsignames tests" begin

    function test_func(a::Int, b::Float64; c="default", d=true, request)
        return a, b, c, d
    end

    args, arg_types, kwarg_names = getsignames(test_func)

    @test args == [:a, :b]
    @test arg_types == [Int, Float64]
    @test kwarg_names == [:c, :d, :request]
end

@testset "parsetype tests" begin
    parsetype(Int, 3) == 3
    parsetype(Int, "3") == 3
    parsetype(Float64, "3") == 3.0
    parsetype(Float64, 3) == 3.0
end

@testset "JSON Nested extract" begin 

    converted = kwarg_struct_builder(Home, Dict(
        :address => "123 main street",
        :owner => Dict(
            :name => "joe",
            :age => 25
        )
    ))

    @test converted == Home("123 main street", Person("joe", 25))

end

@testset "kwarg_struct_builder arrays" begin

    company = kwarg_struct_builder(Company, Dict(
        :name => "acme",
        :employees => [Dict(:name => "joe", :age => 25)],
        :revenues => ["100", "200"],
    ))
    @test company.name == "acme"
    @test length(company.employees) == 1
    @test company.employees[1].name == "joe"
    @test company.employees[1].age == 25
    @test company.revenues == [100, 200]

    roster = kwarg_struct_builder(Roster, Dict(
        :members => [Dict(:name => "joe", :age => 25), nothing],
    ))
    @test length(roster.members) == 2
    @test roster.members[1].name == "joe"
    @test roster.members[1].age == 25
    @test roster.members[2] === nothing

end

@testset "parse_array_value element parsing" begin

    # concrete numerics and enums parsed from strings
    @test parse_array_value(Vector{Int}, ["1", "2"]) == [1, 2]
    @test parse_array_value(Vector{Fruit}, ["1", "2"]) == [apple, banana]

    # abstract element types resolve to concrete values
    @test parse_array_value(Vector{Real}, ["1.5"]) == Real[1.5]

    # unions with Nothing are handled element-wise
    @test parse_array_value(Vector{Union{Int, Nothing}}, ["1", nothing]) == Union{Int, Nothing}[1, nothing]

    # custom structs are built from dicts
    @test parse_array_value(Vector{Person}, [Dict("name" => "joe", "age" => 25)]) == [Person("joe", 25)]

    # dict-typed elements must not be routed through struct_builder
    @test parse_array_value(Vector{Dict{String, Int}}, [Dict("a" => 1)]) == [Dict("a" => 1)]

    # nested arrays keep their structure
    @test parse_array_value(Vector{Vector{Int}}, [["1", "2"], ["3"]]) == [[1, 2], [3]]
end

@testset "splitdef tests" begin
    # Define a function for testing
    function test_func(a::Int, b::Float64; c="default", d=true, request)
        return a, b, c, d
    end

    # Parse the function info
    info = splitdef(test_func)

    @testset "Function name" begin
        @test info.name == :test_func
    end

    @testset "counts" begin
        @test length(info.args) == 2
        @test length(info.kwargs) == 3
        @test length(info.sig) == 5
    end

    @testset "Args" begin 
        @test info.args[1].name == :a
        @test info.args[1].type == Int

        @test info.args[2].name == :b
        @test info.args[2].type == Float64
    end


    @testset "Kwargs" begin
        @test length(info.kwargs) == 3
        @test info.kwargs[1].name == :c
        @test info.kwargs[1].type == Any
        @test info.kwargs[1].default == "default"
        @test info.kwargs[1].hasdefault == true

        @test info.kwargs[2].name == :d
        @test info.kwargs[2].type == Any
        @test info.kwargs[2].default == true
        @test info.kwargs[2].hasdefault == true

        @test info.kwargs[3].name == :request
        @test info.kwargs[3].type == Any
        @test info.kwargs[3].default isa Missing
        @test info.kwargs[3].hasdefault == false
    end

    @testset "Sig_map" begin
        @test length(info.sig_map) == 5
        @test info.sig_map[:a].name == :a
        @test info.sig_map[:a].type == Int
        @test info.sig_map[:b].name == :b
        @test info.sig_map[:b].type == Float64

        @test info.sig_map[:c].name == :c
        @test info.sig_map[:c].type == Any
        @test info.sig_map[:c].default == "default"
        @test info.sig_map[:c].hasdefault == true

        @test info.sig_map[:d].name == :d
        @test info.sig_map[:d].type == Any
        @test info.sig_map[:d].default == true
        @test info.sig_map[:d].hasdefault == true

        @test info.sig_map[:request].name == :request
        @test info.sig_map[:request].type == Any
        @test info.sig_map[:request].default isa Missing
        @test info.sig_map[:request].hasdefault == false
    end
end


@testset "splitdef anonymous function tests" begin
    # Define a function for testing
    
    
    # Parse the function info
    info = getinfo(function(a::Int, b::Float64; c="default", d=true, request)
        return a, b, c, d
    end
    )

    @testset "counts" begin
        @test length(info.args) == 2
        @test length(info.kwargs) == 3
        @test length(info.sig) == 5
    end

    @testset "Args" begin 
        @test info.args[1].name == :a
        @test info.args[1].type == Int

        @test info.args[2].name == :b
        @test info.args[2].type == Float64
    end


    @testset "Kwargs" begin
        @test length(info.kwargs) == 3
        @test info.kwargs[1].name == :c
        @test info.kwargs[1].type == Any
        @test info.kwargs[1].default == "default"
        @test info.kwargs[1].hasdefault == true

        @test info.kwargs[2].name == :d
        @test info.kwargs[2].type == Any
        @test info.kwargs[2].default == true
        @test info.kwargs[2].hasdefault == true

        @test info.kwargs[3].name == :request
        @test info.kwargs[3].type == Any
        @test info.kwargs[3].default isa Missing
        @test info.kwargs[3].hasdefault == false
    end

    @testset "Sig_map" begin
        @test length(info.sig_map) == 5
        @test info.sig_map[:a].name == :a
        @test info.sig_map[:a].type == Int
        @test info.sig_map[:b].name == :b
        @test info.sig_map[:b].type == Float64

        @test info.sig_map[:c].name == :c
        @test info.sig_map[:c].type == Any
        @test info.sig_map[:c].default == "default"
        @test info.sig_map[:c].hasdefault == true

        @test info.sig_map[:d].name == :d
        @test info.sig_map[:d].type == Any
        @test info.sig_map[:d].default == true
        @test info.sig_map[:d].hasdefault == true

        @test info.sig_map[:request].name == :request
        @test info.sig_map[:request].type == Any
        @test info.sig_map[:request].default isa Missing
        @test info.sig_map[:request].hasdefault == false
    end
end

@testset "splitdef do..end syntax" begin


    # Parse the function info
    info = splitdef() do a::Int, b::Float64
        return a, b
    end

    @testset "counts" begin
        @test length(info.args) == 2
        @test length(info.sig) == 2
    end

    @testset "Args" begin 
        @test info.args[1].name == :a
        @test info.args[1].type == Int

        @test info.args[2].name == :b
        @test info.args[2].type == Float64
    end

    @testset "Sig_map" begin
        @test length(info.sig_map) == 2
        @test info.sig_map[:a].name == :a
        @test info.sig_map[:a].type == Int
        @test info.sig_map[:b].name == :b
        @test info.sig_map[:b].type == Float64
    end
end



@testset "splitdef extractor default value" begin
    # Define a function for testing
    f = function(a::Int, house = Json{Home}(house -> house.owner.age >= 25), msg = message; request, b = 3.0)
        return a, house, msg
    end

    # Parse the function info
    info = splitdef(f)

    @testset "counts" begin
        @test length(info.args) == 3
        @test length(info.kwargs) == 2
        @test length(info.sig) == 5
        @test length(info.sig_map) == 5
    end

    @testset "Args" begin 
        @test info.args[1].name == :a
        @test info.args[1].type == Int

        @test info.args[2].name == :house
        @test info.args[2].type == Json{Home}
        @test info.args[2].default isa Json{Home}

        @test info.args[3].name == :msg
        @test info.args[3].type == Dict{String, String} 
    end

    @testset "Kwargs" begin
        @test info.kwargs[1].name == :request
        @test info.kwargs[1].type == Any
        @test info.kwargs[1].default isa Missing
        @test info.kwargs[1].hasdefault == false

        @test info.kwargs[2].name == :b
        @test info.kwargs[2].type == Any
        @test info.kwargs[2].default == 3.0
        @test info.kwargs[2].hasdefault == true
    end

    @testset "Sig_map" begin
        @test info.sig_map[:a].name == :a
        @test info.sig_map[:a].type == Int
        @test info.sig_map[:a].default isa Missing
        @test info.sig_map[:a].hasdefault == false

        @test info.sig_map[:house].name == :house
        @test info.sig_map[:house].type == Json{Home}
        @test info.sig_map[:house].default isa Json{Home}
        @test info.sig_map[:house].hasdefault == true

        @test info.sig_map[:msg].name == :msg
        @test info.sig_map[:msg].type == Dict{String, String}
        @test info.sig_map[:msg].default == Dict("message" => "Hello, World!")
        @test info.sig_map[:msg].hasdefault == true

        @test info.sig_map[:request].name == :request
        @test info.sig_map[:request].type == Any
        @test info.sig_map[:request].default isa Missing
        @test info.sig_map[:request].hasdefault == false

        @test info.sig_map[:b].name == :b
        @test info.sig_map[:b].type == Any
        @test info.sig_map[:b].default == 3.0
        @test info.sig_map[:b].hasdefault == true
    end
end


end