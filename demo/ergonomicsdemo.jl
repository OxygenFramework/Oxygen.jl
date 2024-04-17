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

struct Address
    street::String
    city::String
    state::String
    zip::String
end

struct Person 
    name::String
    age::Int
end

@kwdef struct Sample
    limit::Int =20
    skip::Int = 33
end

struct Parameters
    b::Int
end


@kwdef struct PersonWithDefault
    name::String
    age::Int
    money::Float64 = 100.0
    address::Address = Address("123 Main Street", "Orlando", "FL", "32810")
end

post("/json/partial") do req, p1::JsonFragment{PersonWithDefault}, p2::JsonFragment{PersonWithDefault}
    return Dict("p1" => p1, "p2" => p2)
end

# @get "/headers" function(req, headers::Header{Sample})
#     return headers.payload
# end

# @get "/add/{a}/{b}" function(req, a::String, path::Path{Parameters}, qparams::Query{Sample}, c::Float64=3.6)
#     return (a=a, c=c, path=path, query=qparams)
# end

@get "/path/add/{a}/{b}" function(req, a::Int, path::Path{Parameters}, qparams::Query{Sample}, c::Nullable{Int}=23)
    println(qparams)
    return a + path.payload.b
end

@get "/" function(req)
    "home"
end

# serve()


end