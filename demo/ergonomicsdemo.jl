module ErgonomicsDemo
include("../src/Oxygen.jl")
using .Oxygen
using Base: @kwdef

@kwdef struct Person2
    name::String
    age::Int
    height::Float64
    weight::Float64
    is_employed::Bool
    occupation::String
    salary::Float64
    country_of_origin::String
    favorite_color::String
    number_of_pets::Int
end

p2 = Dict(
    "name" => "John Doe",
    "age" => "30",
    "height" => "6.0",
    "weight" => "180.0",
    "is_employed" => "true",
    "occupation" => "Software Engineer",
    "salary" => "100000.34532",
    "country_of_origin" => "USA",
    "favorite_color" => "blue",
    "number_of_pets" => "2"
)

p = build_struct(Person2, p2)
println(p)

function add(a::Int, b::Int; c::Float64=4.4)
    nothing
end

info = parse_func_info(add)

println(info.args)
println(info.kwargs |> first |> hasdefault)


end