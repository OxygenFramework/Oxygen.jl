module ReflectionTests

using Test
using Oxygen: parse_func_info

function getinfo(f::Function)
    return parse_func_info(f)
end

@testset "parse_func_info tests" begin
    # Define a function for testing
    function test_func(a::Int, b::Float64; c="default", d=true, request)
        return a, b, c, d
    end

    # Parse the function info
    info = getinfo(test_func)

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


@testset "parse_func_info anonymous function tests" begin
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

@testset "parse_func_info do..end syntax" begin


    # Parse the function info
    info = parse_func_info() do a::Int, b::Float64
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


end