module ErgonomicsDemo
include("../src/Oxygen.jl")
using .Oxygen
import .Oxygen: validate, Param, hasdefault, parse_func_info, struct_builder

using StructTypes

using HTTP
using JSON3
using Base: @kwdef
using BenchmarkTools


struct AddParams 
    a::Int
    b::Int
end

# s = @btime StructTypes.constructfrom(AddParams, Dict(:a => "32", :b => "3") )


# addbuilder = struct_builder(AddParams)

# @btime addbuilder(Dict("a" => "32", "b" => "3"))

@kwdef struct Sample
    skip::Int
    limit::Int = 3
end

# methods(Sample) |> first |> Base.code_lowered |> println

struct Parameters
    a::Int
    b::Int
end

@get "/add/{a}/{b}" function(req, path::Path{Parameters}, qparams::Query{Sample}, c::Int=3 )

    println(path)
    println(qparams)
   
    return qparams
end

serve(docs=false, metrics=false)


# @get "/add/{a}/{b}" function(req, path::Path{AddParams})
#     println(path)
# end



# serve()



# # f = function (a::Int, b::Int=4, c::Float64=3.0; message="hello", req=234)
# #     println("wow")
# # end

# function myfunc(a::Int, b::Int; request=3.3)
#     a + b
# end


# details = @btime parse_func_info(myfunc)





# function get_method_definition(f::Function)
#     m = first(methods(f))
#     types = tuple(m.sig.types[2:end]...)
#     method = which(f, types)

#     # Open the file and read the method definition
#     open(string(method.file)) do file
#         lines = readlines(file)
#         start_line = method.line
#         # Assuming the method definition ends with 'end'
#         end_line = findnext(x -> startswith(strip(x), "end"), lines, start_line)
#         return join(lines[start_line:end_line], "\n")
#     end
# end


# get_method_definition(f) |> println


# m = first(methods(f))
# types = tuple(m.sig.types[2:end]...)

# code_string(f, types) |> println


# m = first(methods(f))
# types = tuple(m.sig.types[2:end]...)
# method = which(f,types)

# println(method.file)
# println(method.line)


# println(splitdef(ex))

# splitdef(
#     :($f)
# ) |> println




# wrapexpr(mylambda)



# Base.code_lowered(f) |> println
# Base.code_typed(f) |> println


# println(show(name))


# m = first(methods(f))
# types = tuple(m.sig.types[2:end]...)
# str = code_string(f, types)


# str |> println

# println("here")

# info = parse_func_info(d)
# println(info)

# println(Path)


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


# x = @btime struct_builder(Person2, p2)



# @btime begin
#     p2_symbols = Dict(Symbol(k) => v for (k, v) in p2)
#     s = StructTypes.constructfrom(Person2, p2_symbols)
# end

# println(p)

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