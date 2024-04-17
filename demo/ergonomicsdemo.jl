module ErgonomicsDemo
include("../src/Oxygen.jl")
using .Oxygen
import .Oxygen: validate, Param, hasdefault, parse_func_info, struct_builder, Nullable, extractor, LazyRequest

using Base: @kwdef
using StructTypes
using Dates
using HTTP
using JSON3
using Base: @kwdef
using BenchmarkTools

struct Person 
    name::String
    age::Int
end

@kwdef struct Sample
    limit::Int
    skip::Int = 33
end

struct Parameters
    b::Int
end


@get "/add/{a}/{b}" function(req, a::String, path::Path{Parameters}, qparams::Query{Sample}, c::Float64=3.6)
    return (a=a, path=path, query=qparams)
end

@get "/" function(req)
    "home"
end

serve()


end