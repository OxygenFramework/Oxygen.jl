module ErgonomicsDemo
include("../src/Oxygen.jl")
using .Oxygen
import .Oxygen: validate

using HTTP
using JSON3
using Base: @kwdef
using BenchmarkTools
using ExprTools: splitdef
using Revise
using CodeTracking: code_string, code_expr, definition


struct AddParams 
    a::Int
    b::Int
end

# @get "/add/{a}/{b}" function(req, params::Path{AddParams})
#     return text("$(params.a + params.b)")
# end

# serve()
# function wrapexpr(f::Function)
#     name = gensym()  # Generate a unique symbol
#     ex = Base.code_lowered(f(1, 2))  # Get the lowered form of the function body
#     # new_ex = quote
#     #     function $name(args...; kwargs...)  # Allow any number of arguments of any type
#     #         $(ex.code)  # Interpolate the function body
#     #     end
#     # end
#     println(ex)
# end


# function func_to_expr(f::Function)
#     lowered = Base.code_lowered(f)
#     return [info for info in lowered]  # This will return the code block of the function
# end

# macro function_to_expr(func_def)
#     return esc(:(Expr(:function, $(func_def.args...), $(func_def.body))))
# end


# f = function (a::Int, b::Int=4; message::String="hi")
#     return a + b
# end

# @function_to_expr(f) |> println

# # case 1
# splitdef(
#     :(function(a::Int, b::Int=4; message::String="hi")
#         a + b
#     end)
# ) |> println

# using InteractiveUtils

# case 2
f = function (a::Int, b::Int=4; message="hi")
    a + b
end


function walk_expr(expr::Expr, values=[])
    for arg in expr.args
        if isa(arg, Expr)
            walk_expr(arg, values)
        elseif isa(arg, Symbol) && !startswith(string(arg), "_")
            push!(values, arg)
        end
    end
    return values
end


function extract_func(f::Function)

    info = Base.code_lowered(f)

    # case 1: no defaults 
    if length(info) == 1

    # case 2: has default values
    else
        for c in info
            println(c.code)
            for expr in c.code
                values = walk_expr(expr)
                println(values)  # This will print the values with no leading "_"
            end
            # println(c.slotnames[2:end])
            # println(c.code)
        end
    end
  

end

extract_func(f)

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


ex = Meta.parse("""
function(a::Int, b::Int=4; message::String="hi")
    a + b
end
""")

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

# gen = @btime struct_builder(Person2)

# p = @btime gen(p2)
# println(p)

# function add(a::Int, b::Int; c::Float64=4.4)
#     nothing
# end

# info = parse_func_info(add)

# println(info.args)
# println(info.kwargs |> first |> hasdefault)

struct Person
    name::String
    age::Int
end

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