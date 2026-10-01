module ReflectionTests

using Test
using Base: @kwdef
using Oxygen: splitdef, Json
using Oxygen.Core.Reflection: getsignames, parsetype, kwarg_struct_builder, parse_array_value,
    parse_dict_value, parse_union_value, parse_enum, struct_builder
using Oxygen.Core.Util: parseparam


global message = Dict("message" => "Hello, World!")

# Defined at module scope so its method name (`#N`) differs from its closure
# reference (`var"#N#M"`); this is the bare-anonymous-function case that used
# to shift keyword-argument alignment in `extract_defaults`.
const bare_anon = function(a::Int; b = nothing)
    return a, b
end

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

@kwdef struct Club
    members::Dict{String, Person} = Dict{String, Person}()
end

struct Venue
    name::String
    seats::Dict{String, Person}
end

@kwdef struct Options
    seats::Union{Dict{String, Person}, Nothing} = nothing
    organizer::Union{Person, Nothing} = nothing
end

struct Cat
    meow::String
end

@kwdef struct Shelter
    residents::Vector{Union{Person, Cat, Nothing}} = Vector{Union{Person, Cat, Nothing}}()
    lead::Union{Person, Cat, Nothing} = nothing
end

@kwdef struct Grid
    label::String
    grid::Vector{Vector{Int}} = Vector{Vector{Int}}()
    people::Vector{Union{Person, Nothing}} = Vector{Union{Person, Nothing}}()
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

@testset "parse_enum" begin

    # names are the wire form; integers and integer strings still work
    @test parse_enum(Fruit, "apple") === apple
    @test parse_enum(Fruit, "banana") === banana
    @test parse_enum(Fruit, 1) === apple
    @test parse_enum(Fruit, "2") === banana
    @test parse_enum(Fruit, apple) === apple
    @test_throws ArgumentError parse_enum(Fruit, "nope")
    @test_throws ArgumentError parse_enum(Fruit, 9)

    # every leaf parser funnels into it
    @test parsetype(Fruit, "apple") === apple
    @test parse_array_value(Vector{Fruit}, ["apple", 2]) == [apple, banana]
    @test parse_array_value(Vector{Vector{Fruit}}, [["apple"], [2]]) == [[apple], [banana]]
    @test parse_dict_value(Dict{String,Fruit}, Dict("a" => "banana")) == Dict("a" => banana)
    @test parse_dict_value(Dict{Fruit,Int}, Dict("apple" => 1)) == Dict(apple => 1)
    @test parse_union_value(Union{Fruit,Nothing}, "banana") === banana
end

@testset "parseparam enums" begin

    # path/query params share the JSON-body convention
    @test parseparam(Fruit, "apple") === apple
    @test parseparam(Fruit, "banana") === banana
    @test parseparam(Fruit, "1") === apple
    @test parseparam(Fruit, "2") === banana
    @test parseparam(Fruit, "banana"; escape=false) === banana
    @test_throws ArgumentError parseparam(Fruit, "nope")
    @test_throws ArgumentError parseparam(Fruit, "9")
end

@testset "parse_array_value element parsing" begin

    # concrete numerics and enums parsed from strings
    @test parse_array_value(Vector{Int}, ["1", "2"]) == [1, 2]
    @test parse_array_value(Vector{Fruit}, ["1", "2"]) == [apple, banana]
    @test parse_array_value(Vector{Fruit}, ["apple", "banana"]) == [apple, banana]

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

@testset "parse_dict_value" begin

    # values parsed from strings
    @test parse_dict_value(Dict{String, Int}, Dict("a" => "1")) == Dict("a" => 1)

    # JSON string keys map to Symbol keys
    @test parse_dict_value(Dict{Symbol, Int}, Dict("a" => 1)) == Dict(:a => 1)

    # custom struct values
    @test parse_dict_value(Dict{String, Person}, Dict("joe" => Dict("name" => "joe", "age" => 25))) ==
          Dict("joe" => Person("joe", 25))

    # nested dictionaries and arrays
    @test parse_dict_value(Dict{String, Dict{String, Int}}, Dict("a" => Dict("b" => "2"))) ==
          Dict("a" => Dict("b" => 2))
    @test parse_dict_value(Dict{String, Vector{Person}}, Dict("team" => [Dict("name" => "joe", "age" => 25)])) ==
          Dict("team" => [Person("joe", 25)])

    # unparameterized dictionaries fall back to Any
    @test parse_dict_value(Dict, Dict("a" => 1)) == Dict("a" => 1)
end

@testset "struct_builder dictionaries" begin
    club = kwarg_struct_builder(Club, Dict(:members => Dict("joe" => Dict(:name => "joe", :age => 25))))
    @test club.members == Dict("joe" => Person("joe", 25))

    venue = struct_builder(Venue, Dict("name" => "hall", "seats" => Dict("a" => Dict("name" => "joe", "age" => 25))))
    @test venue.name == "hall"
    @test venue.seats == Dict("a" => Person("joe", 25))

    # nullable dictionary and struct fields
    options = kwarg_struct_builder(Options, Dict(
        :seats => Dict("a" => Dict(:name => "joe", :age => 25)),
        :organizer => Dict(:name => "ann", :age => 30),
    ))
    @test options.seats == Dict("a" => Person("joe", 25))
    @test options.organizer == Person("ann", 30)

    empty_options = kwarg_struct_builder(Options, Dict(:seats => nothing, :organizer => nothing))
    @test empty_options.seats === nothing
    @test empty_options.organizer === nothing
end

@testset "union value parsing" begin

    # heterogeneous vectors pick the union member that fits each element
    @test parse_array_value(Vector{Union{Person, Cat, Nothing}},
                            [Dict("name" => "joe", "age" => 25), Dict("meow" => "m"), nothing]) ==
          Union{Person, Cat, Nothing}[Person("joe", 25), Cat("m"), nothing]

    # primitive unions parse from strings
    @test parse_union_value(Union{Int, String}, "5") === 5
    @test parse_union_value(Union{Int, String}, "abc") == "abc"

    shelter = kwarg_struct_builder(Shelter, Dict(
        :residents => [Dict("name" => "joe", "age" => 25), Dict("meow" => "m")],
        :lead => Dict("meow" => "m"),
    ))
    @test shelter.residents == Union{Person, Cat, Nothing}[Person("joe", 25), Cat("m")]
    @test shelter.lead == Cat("m")

    # omitted multi-type union fields still default to nothing
    empty_shelter = kwarg_struct_builder(Shelter, Dict(:lead => nothing))
    @test empty_shelter.lead === nothing
end

@testset "splitdef collection defaults" begin
    info = splitdef(Grid)

    # required fields before a defaulted field must not corrupt collection defaults
    @test info.sig_map[:grid].default == Vector{Vector{Int}}()
    @test info.sig_map[:grid].hasdefault == true
    @test info.sig_map[:people].default == Vector{Union{Person, Nothing}}()
    @test info.sig_map[:people].hasdefault == true
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

@testset "splitdef bare anonymous function" begin
    info = splitdef(bare_anon)

    @test length(info.args) == 1
    @test info.args[1].name == :a
    @test info.args[1].hasdefault == false

    @test length(info.kwargs) == 1
    @test info.kwargs[1].name == :b
    @test info.kwargs[1].hasdefault == true
    @test info.kwargs[1].default === nothing
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