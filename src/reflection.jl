module Reflection

using ExprTools: splitdef
using CodeTracking: code_string

export Param, hasdefault, parse_params, parse_func_info, 
        has_kwarg_constructor, extract_struct_info, build_struct

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
    expr = Meta.parse(code_string(f, types))

    info = splitdef(expr)
    args    :: Vector{Union{Symbol,Expr}} = info[:args]
    kwargs  :: Vector{Union{Symbol,Expr}} = info[:kwargs]

    return (
        name = info[:name],
        args = parse_params(args), 
        kwargs = parse_params(kwargs),
    )
end

"""
    has_kwarg_constructor(T::Type) :: Bool

Checks if the type `T` has a constructor that takes no positional arguments but only keyword arguments. 
The function returns `true` if such a constructor exists and the keyword arguments match the field names of the type `T`. 
Otherwise, it returns `false`.

# Arguments
- `T::Type`: The type to check for the existence of a keyword-only constructor.

# Returns
- `Bool`: `true` if a keyword-only constructor exists and its keyword arguments match the field names of `T`, `false` otherwise.
"""
function has_kwarg_constructor(T::Type) :: Bool
    constructors = methods(T)
    for constructor in constructors
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
    field_types = [fieldtype(T, name) for name in field_names]
    type_map = Dict(string(name) => fieldtype(T, name) for name in field_names)
    return (names=string.(field_names), types=field_types, map=type_map)
end


"""
    build_struct(TargetType::Type{T}, parameters::Dict{String,String}) where {T}

Constructs an object of type `T` using the parameters in the dictionary `parameters`.
"""
function build_struct(TargetType::Type{T}, parameters::Dict{String,String}) where {T}
    info = extract_struct_info(TargetType)
    has_kwdef = has_kwarg_constructor(TargetType)
    
    param_dict = Dict{Symbol, Any}()
    casted_params = Vector{Any}()

    for param_name in info.names
        # ignore unkown parameters
        if haskey(parameters, param_name)
            param_value = parameters[param_name]
            target_type = info.map[param_name]
            parsed_value = target_type == Any || target_type == String ? param_value : parse(target_type, param_value)
            # only add to the dictionary if the constructor is keyword-only
            if has_kwdef
                param_dict[Symbol(param_name)] = parsed_value
            # otherwise, add to the positional arguments
            else
                push!(casted_params, parsed_value)
            end
        end
    end

    # return the constructed object
    return has_kwdef ? TargetType(;param_dict...) : TargetType(casted_params...)
end

end