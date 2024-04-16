module Reflection
using StructTypes
using Base: @kwdef
using ..Types

export parse_func_info, struct_builder, extract_struct_info

"""
Helper function to access the underlying value of any global references
"""
function getargvalue(arg)
    return isa(arg, GlobalRef) ? getfield(arg.mod, arg.name) : arg
end


"""
Return all parameter name & types and keyword argument names from a function
"""
function getsignames(f::Function; start=3)
    return getsignames(methods(f), start=start)
end

"""
Return parameter name & types and keyword argument names from a list of methods
"""
function getsignames(func_methods::Base.MethodList; start=3)
    sig = Vector{Symbol}()
    types = Vector{Type}()
    kwarg_names = Vector{Symbol}()
    for m in func_methods
        for argname in Base.method_argnames(m)[start:end]
            if argname ∉ sig
                push!(sig, argname)
            end
        end
        for type in fieldtypes(m.sig)[start:end]
            if type ∉ types
                push!(types, type)
            end
        end
        for kwarg in Base.kwarg_decl(m)
            if kwarg ∉ kwarg_names
                push!(kwarg_names, kwarg)
            end
        end
    end
    return sig, types, kwarg_names
end



"""
The args is a vector that follows this shape like This
[
    kwarg defaults...,
    slots..., 
    positional defaults...
]
"""
function splitargs(args::Vector)

    param_defaults = Vector{Any}()
    kwarg_defaults = Vector{Any}()

    encountered_slot = false
    for arg in args
        if isa(arg, Core.SSAValue)
            continue
        elseif isa(arg, Core.SlotNumber)
            encountered_slot = true
        elseif !encountered_slot
            push!(kwarg_defaults, getargvalue(arg))
        else
            push!(param_defaults, getargvalue(arg))
        end
    end

    return param_defaults, kwarg_defaults
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
            if !isa(expr, Expr) || expr.head != :call || startswith(string(expr), "Core.") || !isa(first(expr.args), Core.SlotNumber)
                continue
            end 
  
            # get the default values for this expression
            p_defaults, kw_defaults = splitargs(expr.args[2:end])


            # store the default values for params
            if !isempty(p_defaults)
                # we reverse, because each subsequent expression should show more defaults,
                # so we need to keep updating them as we see them.
                for (name, value) in zip(reverse(param_names), reverse(p_defaults))
                    param_defaults[name] = value
                end
            end

            # store the default values for kwargs
            if !isempty(kw_defaults)
                for (name, value) in zip(kwarg_names, kw_defaults)
                    kwarg_defaults[name] = value
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

    func_methods = methods(f)

    # Extract parameter names and types
    param_names, param_types, kwarg_names = getsignames(func_methods)

    # Convert to low level IR code
    info = Base.code_lowered(f)

    # Extract default values
    param_defaults, kwarg_defaults = extract_defaults(info, param_names, kwarg_names)

    # Create a list of Param objects from parameters
    params = Vector{Param}()
    for (name, type) in zip(param_names, param_types)
        if haskey(param_defaults, name)
            push!(params, Param(name=name, type=type, default=param_defaults[name], hasdefault=true))
        else
            push!(params, Param(name=name, type=type))
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
        name = first(func_methods).name,
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
    has_kwdef = has_kwdef_constructor(T)
    params_with_symbols = Dict(Symbol(k) => v for (k, v) in params)    
    # case 1: Use slower converter to handle structs with keyword args
    if has_kwdef
        return kwarg_struct_builder(T, params_with_symbols)
    # case 2: Use faster converter to handle structs with no defaults
    else
        return StructTypes.constructfrom(T, params_with_symbols)
    end
end

"""
    has_kwdef_constructor(T::Type) :: Bool

Returns true if type `T` has a constructor that takes only keyword arguments and matches the order and field names of `T`.
Otherwise, it returns `false`.

Practically, this check is used to check if `@kwdef` was used to define the struct.
"""
function has_kwdef_constructor(T::Type) :: Bool
    fieldnames = Base.fieldnames(T)
    for constructor in methods(T)
        if length(Base.method_argnames(constructor)) == 1 && 
            Tuple(Base.kwarg_decl(constructor)) == fieldnames
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

function kwarg_struct_builder(TargetType::Type{T}, params::Dict{Symbol,String}) where {T}
    
    # This should run once for setup
    info = extract_struct_info(TargetType)
    param_dict = Dict{Symbol, Any}()

    for param_name in info.names
        # ignore unkown parameters
        if haskey(params, param_name)
            param_value = params[param_name]
            target_type = info.map[param_name]
            parsed_value = target_type == Any || target_type == String ? param_value : parse(target_type, param_value)
            param_dict[param_name] = parsed_value
        end
    end
    
    return TargetType(;param_dict...)
end

end