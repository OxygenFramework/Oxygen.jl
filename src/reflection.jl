module Reflection
using StructTypes
using Base: @kwdef
using ..Types
# using ExprTools: splitdef
# using CodeTracking: code_string

export parse_func_info, struct_builder, extract_struct_info


"""


The args is a vector that follows this shape like This
[
    kwarg defaults...,
    slots..., 
    positional defaults...
]
"""
function splitargs(args::Vector)
    kwarg_defaults = Vector{Any}()
    param_defaults = Vector{Any}()

    encountered_slot = false

    for arg in args
        if isa(arg, Core.SlotNumber)
            encountered_slot = true
        elseif !encountered_slot
            push!(kwarg_defaults, arg)
        else
            push!(param_defaults, arg)
        end
    end

    return kwarg_defaults, param_defaults
end

"""
This function extract default values from a list of expressions

Example:

[:a, :b, :c]            - positional args
hi : String             - first kwarg default value
5 : Int64               - second kwarg default value
_1 : Core.SlotNumber    - 1st arg (self ref)
_2 : Core.SlotNumber    - 2nd arg
_3 : Core.SlotNumber    - 3rd arg
_4 : Core.SlotNumber    - 4th arg

[:a, :b]                - positional args
_2 : Core.SlotNumber    - 2nd arg
_3 : Core.SlotNumber    - 3rd arg
3.4 : Float64           - default value for the 2nd positional arg "c"

[:a]                    - positional args
_2 : Core.SlotNumber    - 2nd arg (1st positional arg)
4 : Int64               - default value for the first positional arg "b"
3.4 : Float64           - default value for the second positional arg "c"
"""
function extract_defaults(info, param_names, kwarg_names)

    # store default values
    param_defaults = Dict()
    kwarg_defaults = Dict()

    for c in info

        temp_kwarg_defaults = []
        for expr in c.code

            """
            If a kwarg has no default value it messes with the expr ordering, which means we 
            need to extract it early and store it for later use. If we can parse default values
            normally then the temp values won't get used.
            """
            if !isa(expr, Expr) && !isa(expr, Core.ReturnNode)
                push!(temp_kwarg_defaults, expr)
            end
         
            
            """
            1.) skip any non expressions
            2.) skip any non call expressions
            3.) skip any Core expressions
            """
            if !isa(expr, Expr) || expr.head != :call || startswith(string(expr), "Core.")
                continue
            end    
            
            # get the default values for this expression
            kw_defaults, p_defaults = splitargs(expr.args[2:end])

            # store the default values for kwargs
            if !isempty(kw_defaults)
                for (name, value) in zip(kwarg_names, kw_defaults)
                    kwarg_defaults[name] = value
                end
            end

            # store the default values for params
            if !isempty(p_defaults)
                # we reverse, because each subsequent expression should show more defaults,
                # so we need to keep updating them as we see them.
                for (name, value) in zip(reverse(param_names), reverse(p_defaults))
                    param_defaults[name] = value
                end
            end

        end

        """
        If we haven't found any defaults normally, then that means a kwarg has no default value
        and is altering the structure of the expressions. When this happens use the temp kwarg values
        parsed from early and insert these.
        """
        if isempty(kwarg_defaults) && !isempty(temp_kwarg_defaults)
            for (name, value) in zip(kwarg_names, temp_kwarg_defaults)
                kwarg_defaults[name] = value
            end
        end
    end

    return param_defaults, kwarg_defaults

end

function parse_func_info(f::Function; start=2)

    method = first(methods(f))

    # Extract parameter names and types
    param_names = Base.method_argnames(method)[start:end]
    param_types = fieldtypes(method.sig)[start:end]
    kwarg_names = Base.kwarg_decl(method) 

    # Convert to low level IR code
    info = Base.code_lowered(f)

    # Extract default values
    param_defaults, kwarg_defaults = extract_defaults(info, param_names, kwarg_names)


    # Create a list of Param objects from parameters
    params = Vector{Param}()
    for (name, type) in zip(param_names, param_types)
        try 
            if haskey(param_defaults, name)
                push!(params, Param(name=name, type=type, default=param_defaults[name], hasdefault=true))
            else
                push!(params, Param(name=name, type=type))
            end
        catch
            println(name, type, param_defaults, kwarg_defaults)
        end
    end

    # Create a list of Param objects from keyword arguments
    keyword_args = Vector{Param}()
    for name in kwarg_names
        # Don't infer the type of the keyword argument, since julia doesn't support types on kwargs
        if haskey(kwarg_defaults, name)
            push!(keyword_args, Param(name=name, type=Any, default=kwarg_defaults[name], hasdefault=true))
        else
            push!(keyword_args, Param(name=name, type=Any))
        end
    end

    sig_params = vcat(params, keyword_args)

    return (
        name = method.name,
        args = params,
        kwargs = keyword_args,
        sig = sig_params,
        sig_map = Dict{Symbol,Param}(param.name => param for param in sig_params)
    )
end




"""
    struct_builder(::Type{T}, parameters::Dict{String,String}) where {T}

Constructs an object of type `T` using the parameters in the dictionary `parameters`.
"""
function struct_builder(::Type{T}, params::Dict{String,String}) :: T where {T}
    params_with_symbols = Dict(Symbol(k) => v for (k, v) in params)

    # property_names = extract_struct_info(T).names
    # for name in property_names
    #     if !haskey(params_with_symbols, name)
    #         params_with_symbols[name] = missing
    #     end
    # end

    return StructTypes.constructfrom(T, params_with_symbols)
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
    type_map = Dict(name => fieldtype(T, name) for name in field_names)
    return (names=field_names, map=type_map)
end

# """
#     struct_builder(TargetType::Type{T}, parameters::Dict{String,String}) where {T}

# Constructs an object of type `T` using the parameters in the dictionary `parameters`.
# """
# function struct_builder(TargetType::Type{T}, params::Dict{String,String}) where {T}

#     # This should run once for setup
#     info = extract_struct_info(TargetType)
#     has_kwdef = has_kwdef_constructor(TargetType)

#     # Loops over parameters and converts the value to the correct type
#     function parser(func::Function, parameters::Dict{String,String})
#         for param_name in info.names
#             # ignore unkown parameters
#             if haskey(parameters, param_name)
#                 param_value = parameters[param_name]
#                 target_type = info.map[param_name]
#                 parsed_value = target_type == Any || target_type == String ? param_value : parse(target_type, param_value)
#                 func(param_name, parsed_value)
#             end
#         end
#     end

#     # Used to build the struct using keyword args
#     function kwargbuilder(parameters::Dict{String,String}) :: T
#         param_dict = Dict{Symbol, Any}()
#         parser(parameters) do name, value
#             param_dict[Symbol(name)] = value
#         end
#         return TargetType(;param_dict...)
#     end

#     # Used to build the struct using positional args
#     function seqbuilder(parameters::Dict{String,String}) :: T
#         casted_params = Vector{Any}()
#         parser(parameters) do _, value
#             push!(casted_params, value)
#         end
#         return TargetType(casted_params...)
#     end

#     return has_kwdef ? kwargbuilder(params) : seqbuilder(params)
# end






# """
# Parse arguments from a function definition in Julia.

#     This function handles four scenarios:
    
#     1. The argument has no type definition or default value.
#     2. The argument has a type definition but no default value.
#     3. The argument has a default value but no type definition.
#     4. The argument has both a type definition and a default value.    
# """
# function parse_params(params::Vector{Union{Symbol,Expr}}) :: Vector{Param}
#     param_info = Vector{Param}()
#     for param in params
#         if isa(param, Expr)
#             if param.head == :kw
#                 # Parameter with type and default value
#                 name = isa(param.args[1], Expr) ? param.args[1].args[1] : param.args[1]
#                 type = isa(param.args[1], Expr) ? eval(param.args[1].args[2]) : Any
#                 default = param.args[2]
#                 push!(param_info, Param(name, type, default))
#             elseif param.head == :(::)
#                 # Parameter with type but no default value
#                 name = param.args[1]
#                 type = eval(param.args[2])
#                 push!(param_info, Param(name, type, missing))
#             elseif param.head == :(=)
#                 # Parameter with default value but no type
#                 name = param.args[1]
#                 default = param.args[2]
#                 push!(param_info, Param(name, Any, default))
#             end
#         else
#             # Parameter with no type or default value
#             name = param
#             push!(param_info, Param(name, Any, missing))
#         end
#     end
#     return param_info
# end



# """
#     parse_func_info(f::Function)

# Extract information from a function definition.
# This function extracts the name of the function, the arguments, and the keyword arguments from a function definition.
# """
# function parse_func_info(f::Function)
#     m = first(methods(f))
#     types = tuple(m.sig.types[2:end]...)
#     str = code_string(f, types)
#     expr = Meta.parse(str)

#     info = splitdef(expr)
#     args    :: Vector{Union{Symbol,Expr}} = get(info, :args, [])
#     kwargs  :: Vector{Union{Symbol,Expr}} = get(info, :kwargs, [])

#     return (
#         name = info[:name],
#         args = parse_params(args), 
#         kwargs = parse_params(kwargs),
#     )
# end


end
