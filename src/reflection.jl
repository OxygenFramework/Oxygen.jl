module Reflection

using ExprTools: splitdef
using CodeTracking: code_string
# using ..Extractors

export Param, hasdefault, parse_func_info, struct_builder

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



"""
    parse_func_info(f::Function)

Extract information from a function definition.
This function extracts the name of the function, the arguments, and the keyword arguments from a function definition.
"""
function parse_func_info(f::Function)
    m = first(methods(f))
    types = tuple(m.sig.types[2:end]...)
    str = code_string(f, types)
    expr = Meta.parse(str)

    info = splitdef(expr)
    args    :: Vector{Union{Symbol,Expr}} = get(info, :args, [])
    kwargs  :: Vector{Union{Symbol,Expr}} = get(info, :kwargs, [])

    return (
        name = info[:name],
        args = parse_params(args), 
        kwargs = parse_params(kwargs),
    )
end

"""
    has_kwdef_constructor(T::Type) :: Bool

Returns true if type `T` has a constructor that takes only keyword arguments and matches the order and field names of `T`.
Otherwise, it returns `false`.

Practically, this check is used to check if `@kwdef` was used to define the struct.
"""
function has_kwdef_constructor(T::Type) :: Bool
    for constructor in methods(T)
        if length(Base.method_argnames(constructor)) == 1 && 
            Tuple(Base.kwarg_decl(constructor)) == Base.fieldnames(T)
            return true
        end
    end
    return false
end

# Function to extract field names, types, and default values
function extract_struct_info(T::Type)
    field_names = fieldnames(T)
    type_map = Dict(string(name) => fieldtype(T, name) for name in field_names)
    return (names=string.(field_names), map=type_map)
end


"""
    struct_builder(TargetType::Type{T}, parameters::Dict{String,String}) where {T}

Constructs an object of type `T` using the parameters in the dictionary `parameters`.
"""
function struct_builder(TargetType::Type{T}) :: Function where {T}

    # This should run once for setup
    info = extract_struct_info(TargetType)
    has_kwdef = has_kwdef_constructor(TargetType)

    # Loops over parameters and converts the value to the correct type
    function parser(func::Function, parameters::Dict{String,String})
        for param_name in info.names
            # ignore unkown parameters
            if haskey(parameters, param_name)
                param_value = parameters[param_name]
                target_type = info.map[param_name]
                parsed_value = target_type == Any || target_type == String ? param_value : parse(target_type, param_value)
                func(param_name, parsed_value)
            end
        end
    end

    # Used to build the struct using keyword args
    function kwargbuilder(parameters::Dict{String,String}) :: T
        param_dict = Dict{Symbol, Any}()
        parser(parameters) do name, value
            param_dict[Symbol(name)] = value
        end
        return TargetType(;param_dict...)
    end

    # Used to build the struct using positional args
    function seqbuilder(parameters::Dict{String,String}) :: T
        casted_params = Vector{Any}()
        parser(parameters) do _, value
            push!(casted_params, value)
        end
        return TargetType(casted_params...)
    end

    return has_kwdef ? kwargbuilder : seqbuilder
end

end