module ErgonomicsDemo
# include("../src/Oxygen.jl")
# using .Oxygen

struct Body{T}
    data::T
end

struct Form{T}
    data::T
end

struct MyForm
    name::String
    email::String
end

struct Person
    name::String
    email::String
    age::Int
end

# @get "/thing/{a}/{b}" function(req, data::Form{MyForm}, body::Body{Person})

# end


# @get "/other/{a}/{b}" function(req, a::Path{String}, b::Path{String}, c::Query{Int}, data::Form{MyForm}, body::Body{Person})

# end

using ExprTools: splitdef
using CodeTracking: code_string

struct Param{T}
    name::Symbol
    type::Type{T}
    default::Union{T, Missing}
end

"""
    hasdefault(param::Param{T}) where T

Check if a parameter has a default value.
# Arguments
- `param::Param{T}`: The parameter to check.

# Returns
- `Boolean`: Returns `true` if the parameter has a default value, `false` otherwise.
"""
function hasdefault(param::Param{T}) :: Bool where T
    # Check if Missing is a subtype of T, or if the default is not Missing
    return ismissing(param.default) ? Missing <: T : true
end



"""
Parse arguments from a function definition in Julia.

    This function handles four scenarios:
    
    1. The argument has no type definition or default value.
    2. The argument has a type definition but no default value.
    3. The argument has a default value but no type definition.
    4. The argument has both a type definition and a default value.    
"""
function parse_params(params::Vector{Union{Symbol,Expr}}) :: Vector{Param}
    param_info = Vector{Param}()
    for param in params
        if isa(param, Expr)
            if param.head == :kw
                # Parameter with type and default value
                name = isa(param.args[1], Expr) ? param.args[1].args[1] : param.args[1]
                type = isa(param.args[1], Expr) ? eval(param.args[1].args[2]) : Any
                default = param.args[2]
                push!(param_info, Param(name, type, default))
            elseif param.head == :(::)
                # Parameter with type but no default value
                name = param.args[1]
                type = eval(param.args[2])
                push!(param_info, Param(name, type, missing))
            elseif param.head == :(=)
                # Parameter with default value but no type
                name = param.args[1]
                default = param.args[2]
                push!(param_info, Param(name, Any, default))
            end
        else
            # Parameter with no type or default value
            name = param
            push!(param_info, Param(name, Any, missing))
        end
    end
    return param_info
end

function parse_func_info(f::Function) #:: Dict{Symbol,Union{Symbol,Vector{Param}}}
    m = first(methods(f))
    types = tuple(m.sig.types[2:end]...)
    expr = Meta.parse(code_string(f, types))

    info = splitdef(expr)
    args    :: Vector{Union{Symbol,Expr}} = info[:args]
    kwargs  :: Vector{Union{Symbol,Expr}} = info[:kwargs]

    return Dict(
        :name => info[:name],
        :args => parse_params(args), 
        :kwargs => parse_params(kwargs),
    )
end

function f(x::Int, l, y::Float64=.4, g="hi"; a::Int = 3, b::Int, c = "hello world", d)
    if x % 2 == 0
        return "done"
    else
        3.0
    end
end


info = parse_func_info(f)
println(typeof(info[:args]))
# for (k,v) in info
#     # println(k, " - ", v)
#     println(v)
#     println()
# end


using Base: @kwdef

@kwdef struct Pagination
    skip::Int = 0
    limit::Int
end

# Function to extract field names, types, and default values
function extract_struct_info(T::Type)
    field_names = fieldnames(T)
    field_types = [fieldtype(T, name) for name in field_names]
    
    return (names=field_names, types=field_types)
end

# Example usage
info = extract_struct_info(Pagination)
println("Field names: ", info.names)
println("Field types: ", info.types)
# println("Default values: ", info.defaults)



end