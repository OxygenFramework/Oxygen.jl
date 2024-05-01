module ReflectionTests

using Test
using Base: @kwdef
using Oxygen: splitdef, Json
using Oxygen.Core.Reflection: getsignames, parsetype, kwarg_struct_builder


global message = Dict("message" => "Hello, World!")

struct Person
    name::String
    age::Int
end

@kwdef struct Home
    address::String
    owner::Person
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