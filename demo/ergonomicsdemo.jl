module ErgonomicsDemo
include("../src/Oxygen.jl")
using .Oxygen
import .Oxygen: validate, Param, hasdefault, parse_func_info, struct_builder, Nullable, LazyRequest, Extractor

using Base: @kwdef
using StructTypes
using Dates
using HTTP
using JSON3
using Base: @kwdef
using BenchmarkTools

# struct Address
#     street::String
#     city::String
#     state::String
#     zip::String
# end

# struct Person 
#     name::String
#     age::Int
# end

# @kwdef struct Sample
#     limit::Int =20
#     skip::Int = 33
# end

# struct Parameters
#     b::Int
# end


# @kwdef struct PersonWithDefault
#     name::String
#     age::Int
#     money::Float64 = 100.0
#     address::Address = Address("123 Main Street", "Orlando", "FL", "32810")
# end

# @get "/query" function(req, query = Query(Sample))
#     return query.payload |> json
# end

# post("/json/partial") do req, p1::JsonFragment{PersonWithDefault}, p2::JsonFragment{PersonWithDefault}
#     return Dict("p1" => p1, "p2" => p2)
# end

# @get "/headers" function(req, headers::Header{Sample})
#     return headers.payload
# end

# # @get "/add/{a}/{b}" function(req, a::String, path::Path{Parameters}, qparams::Query{Sample}, c::Float64=3.6)
# #     return (a=a, c=c, path=path, query=qparams)
# # end

# @get "/path/add/{a}/{b}" function(req, a::Int, path::Path{Parameters}, qparams::Query{Sample}, c::Nullable{Int}=23)
#     println(qparams)
#     return a + path.payload.b
# end

# @get "/" function(req)
#     "home"
# end

# # serve()

@kwdef struct Sample
    limit::Int =20
    skip::Int = 33
end

@kwdef struct Container{T}
    n::T
    sample::Sample
end

global thing = 234

f = function myfunc(req::HTTP.Request, query = Query(Sample), header = Json(Container{Int}), a=5, b=10; c="wow", d=thing, request)

    function dothing(a)
        println(a)
    end

    dothing(3)
    function another(a)
        println(a)
    end

    another("Hi")

    return query.payload |> json
end 

# for m in methods(f)
#     Base.kwarg_decl(m) |> println
# end


# info = parse_func_info(f)

# for x in info.kwargs
#     println(x)
# end
# for (k,v) in info.sig_map
#     println(k, " : ", v)
# end 

# println(p.default)
# println(typeof(p.default))
# println(isstructtype(typeof(p.default)))

a = Query(Sample(10, 20))
# b = Query(Sample)
# c = Query(Sample, x -> x.limit > 10)
# d = Query{Sample}


println(fieldnames(a.type))


# println(a)
# println(b)
# println(c)
# println(d)

# c.validate(Sample(11, 20)) |> println

# println(fieldnames(typeof(x)))
# println(x isa Extractor)

# inner_type = gettype(param) |> fieldtypes |> first
# field_names = fieldnames(inner_type)
# push!(pathparams, field_names...)

# function func_to_expr_func(func_def)
#     return Expr(:quote, func_def)
# end


# println(func_to_expr_func(f))


# ex = :(function f(a,b)
#     a + b
# end)



# using ExprTools

# println(splitdef(ex))



# for p in parse_func_info(f).sig
#     println(p)
# end


end