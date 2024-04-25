module ErgonomicsDemo
include("../src/Oxygen.jl")
using .Oxygen
import .Oxygen: validate, Param, hasdefault, splitdef, struct_builder, Nullable, LazyRequest, Extractor

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

@kwdef struct Sample
    limit::Int = 20
    skip::Int = 33
end

# struct Parameters
#     b::Int
# end


# @kwdef struct PersonWithDefault
#     name::String
#     age::Int
#     money::Float64 = 100.0
#     address::Address = Address("123 Main Street", "Orlando", "FL", "32810")
# end


# post("/json/partial") do req, p1::JsonFragment{PersonWithDefault}, p2::JsonFragment{PersonWithDefault}
#     return Dict("p1" => p1, "p2" => p2)
# end

# @get "/headers" function(req, headers = Header(Sample, s -> s.limit < 30))
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

# serve()

# @kwdef struct Sample
#     limit::Int =20
#     skip::Int = 33
# end

# @kwdef struct Container{T}
#     n::T
#     sample::Sample
# end


"""


-- Using lambda as a function argument
CodeInfo(
1 ─ %1 = Base.getproperty(headers, :payload)
└──      return %1
)
CodeInfo(
1 ─ %1 = Main.ErgonomicsDemo.Sample
│        #5 = %new(Main.ErgonomicsDemo.:(var"#5#7"))
│   %3 = #5
│   %4 = Main.ErgonomicsDemo.Header(%1, %3)
│   %5 = (#self#)(req, %4)
└──      return %5
)

- using a named function as an argument
CodeInfo(
1 ─ %1 = Base.getproperty(headers, :payload)
└──      return %1
)
CodeInfo(
1 ─ %1 = Main.ErgonomicsDemo.Header(Main.ErgonomicsDemo.Sample, Main.ErgonomicsDemo.x)
│   %2 = (#self#)(req, %1)
└──      return %2
)

"""


# f = function(req, headers = Header(Sample, s -> s > 30))
#     return headers.payload
# end

# function test_func(a::Int, b::Float64; c="default", d=true, myrequest)
#     return a, b, c, d
# end


@get "/singlearg" function(req; request)

    return text("Hello World")
end

# serve()

# f = function(req; request)
#     return "Hello World"
# end

# info = splitdef(f)
# for x in info.sig
#     println(x)
# end



# function reconstruct(infovec::Vector{Core.CodeInfo})
#     return vcat(reconstruct.(infovec)...)
# end

# function reconstruct(info::Core.CodeInfo)

#     # create a unique flag for each call to mark missing values
#     NO_VALUES = gensym()
    
#     sig_index = nothing

#     # create a dictionary of statements
#     statements = Dict{Core.SSAValue, Any}()
#     assignments = Dict{Core.SlotNumber, Any}()
    
#     for (index, expr) in enumerate(info.code)

#         ssa_index = Core.SSAValue(index)
#         statements[ssa_index] = expr 

#         if expr isa Expr
#             if expr.head == :(=)
#                 (lhs, rhs) = expr.args
#                 assignments[lhs] = eval(rhs)
        
#             # identify the function signature
#             elseif isdefined(expr, :args) && expr.head == :call
#                 first_arg = first(expr.args) 
#                 if first_arg isa Core.SlotNumber && first_arg.id == 1
#                     sig_index = ssa_index
#                 end
#             end
#         end     
#     end


#     function build(values::AbstractVector)
#         return build.(values)
#     end

#     function build(expr::Expr)
#         expr.args = build.(expr.args)
#         return expr
#     end

#     function build(ssa::Core.SSAValue)
#         return build(statements[ssa])
#     end

#     function build(slot::Core.SlotNumber)
#         value = get(assignments, slot, NO_VALUES)
#         return build(value)
#     end

#     function build(value::Any)
#         return value
#     end

#     # exit early if no sig is found
#     if isnothing(sig_index)
#         return []
#     end 

#     sig_expr = deepcopy(statements[sig_index])

#     # Recrusively build an expression of the actual type of each argument in the function signature
#     evaled_sig = build(statements[sig_index])

#     default_values = []

#     for (sym, value) in zip(sig_expr.args, evaled_sig.args)
#         # only 
#         if value != NO_VALUES && value isa Expr
#             push!(default_values, eval(value))
#         else
#             push!(default_values, sym)
#         end
#     end

#     return default_values
# end


# info = Base.code_lowered(f)
# defaults = reconstruct(info)
# println(defaults)

# for code in info
#     println("--------------")
#     reconstruct(code)
# end

# info = splitdef(f)
# for param in info.args
#     println(param.default)
# end

# global thing = 234

# f = function myfunc(req::HTTP.Request, query = Query(Sample), a=5, b=10; c="wow", request)

#     function dothing(a)
#         println(a)
#     end

#     dothing(3)
#     function another(a)
#         println(a)
#     end

#     another("Hi")

#     return query.payload |> json
# end 


# f = function(req, query = Query(Sample))
#     return query.payload |> json
# end

# info = splitdef(f)

# for x in info.args
#     println(x)
# end



end