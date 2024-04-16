module ErgonomicsDemo
include("../src/Oxygen.jl")
using .Oxygen
import .Oxygen: validate, Param, hasdefault, parse_func_info, struct_builder, Nullable, extractor

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


req = HTTP.Request("GET", "/", [], """{ "persond": {"name": "joe", "age": 25} }""")
param = Param(:persond, PartialJson{Person}, missing, false)
p = extractor(param, req).payload
println(p)

# struct AddParams 
#     a::Int
#     b::Int
# end



# Base.@kwdef struct Sample
#     limit::Int
#     skip::Int = 33
# end

# struct Parameters
#     b::Int
# end


# validate(s::Sample) = s.skip < 10


# @get "/add/{a}/{b}" function(req, a::String, path::Path{Parameters}, qparams::Query{Sample}, c::Nullable{Int}=23)
#     return (a=a, path=path, query=qparams)
# end

# @get "/" function(req)
#     "home"
# end

# @get "/other" function()
#     "other"
# end

# serve()

# @kwdef struct Person2
#     name::String
#     age::Int
#     height::Float64
#     weight::Float64
#     is_employed::Bool
#     occupation::String
#     salary::Float64
#     country_of_origin::String
#     favorite_color::String
#     number_of_pets::Int
# end

# p2 = Dict(
#     "name" => "John Doe",
#     "age" => "30",
#     "height" => "6.0",
#     "weight" => "180.0",
#     "is_employed" => "true",
#     "occupation" => "Software Engineer",
#     "salary" => "100000.34532",
#     "country_of_origin" => "USA",
#     "favorite_color" => "blue",
#     "number_of_pets" => "2"
# )


# function add(a::Int, b::Int; c::Float64=4.4)
#     nothing
# end

# info = parse_func_info(add)

# println(info.args)
# println(info.kwargs |> first |> hasdefault)

# struct Person
#     name::String
#     age::Int
# end

# req = HTTP.Request("GET", "/", [], """{"name": "nathan", "age": 25}""")

# # validate(p::Person) = p.age < 3

# p = extract(Json{Person}, :person, req)
# println(p)




# req = HTTP.Request("GET", "/", [], """3.5""")

# p = extract(Form{Float64}, :value, req)
# println(p)



# req = HTTP.Request("GET", "/", [], """name=nathan&age=25""")

# extract = extractor(Form{Person}, :form)
# extract(req) |> println
# extract(req) |> println



# req = HTTP.Request("GET", "/person/nathan/20", [])

# req.context[:params] = Dict(
#     "name" => "john",
#     "age" => "20"
# )

# # validate(p::Person) = p.age < 20

# extract = extractor(Path{Person}, :pathvalues)
# extract(req) |> println


# req = HTTP.Request("GET", "/person?name=joe&age=30", [])

# # validate(p::Person) = p.age < 20

# extract = extractor(Query{Person}, :queryvalues)
# extract(req) |> println


# req = HTTP.Request("GET", "/person", ["name" => "joe", "age" => "19"])

# # validate(p::Person) = p.age > 20

# extract = extractor(Header{Person}, :headervalues)
# extract(req) |> println



end