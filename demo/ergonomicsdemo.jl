module ErgonomicsDemo
using Oxygen
import Oxygen: validate, Param, hasdefault, splitdef, struct_builder, Nullable, LazyRequest, Extractor

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
    limit::Int = 20
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


@get "/add/{a}/{b}" function(req, a::String, path::Path{Parameters}, qparams::Query{Sample}, c::Float64=3.6)
    return (a=a, c=c, path=path, query=qparams)
end

@get "/headers" function(req, headers = Header(Sample, s -> s.limit < 30))
    return headers.payload
end

@post "/json" function(req, data = Json(PersonWithDefault, p -> p.value < 10 ))
    return data.payload
end

@get "/" function(req)
    "home"
end

serve()

end