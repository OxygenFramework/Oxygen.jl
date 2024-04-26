module Reflection
using StructTypes
using Base: @kwdef
using ..Types

export splitdef, struct_builder, extract_struct_info

"""
Helper function to access the underlying value of any global references
"""
function getargvalue(arg)
    return isa(arg, GlobalRef) ? getfield(arg.mod, arg.name) : arg
end


"""
Return all parameter name & types and keyword argument names from a function
"""
function getsignames(f::Function; start=2)
    return getsignames(methods(f), start=start)
end

"""
Return parameter name & types and keyword argument names from a list of methods
"""
function getsignames(func_methods::Base.MethodList; start=2)
    arg_names = Vector{Symbol}()
    arg_types = Vector{Type}()
    kwarg_names = Vector{Symbol}()

    # track position & types of parameters in the function signature
    positions = Dict{Symbol, Int}()
    for m in func_methods
        argnames = Base.method_argnames(m)[start:end]
        argtypes = fieldtypes(m.sig)[start:end]
        for (i, (argname, type)) in enumerate(zip(argnames, argtypes))
            if argname ∉ arg_names
                push!(arg_names, argname)
                push!(arg_types, type)
                positions[argname] = i
            end
        end
        for kwarg in Base.kwarg_decl(m)
            if kwarg ∉ kwarg_names && kwarg != :...
                push!(kwarg_names, kwarg)
            end
        end
    end
    return arg_names, arg_types, kwarg_names
end


"""
This function extract default values from a list of expressions

The args parameter is a vector that follows this shape like This
[
    function_name...,
    UnionTypes...,
    kwarg defaults...,
    slots..., 
    positional defaults...
]
"""
function splitargs(args::Vector, func_name::Symbol)
    param_defaults = Vector{Any}()
    kwarg_defaults = Vector{Any}()
    encountered_slot = false

    for arg in args
        # # check if this is a function name
        # if arg isa Core.GlobalRef && startswith(String(arg.name), "$func_name#")
        #     continue
        # elseif isa(arg, Core.SSAValue)
        #     continue
        if isa(arg, Core.SlotNumber)
            encountered_slot = true
        elseif !encountered_slot
            push!(kwarg_defaults, getargvalue(arg))
        else
            push!(param_defaults, getargvalue(arg))
        end
    end
    return param_defaults, kwarg_defaults
end

function walkargs(predicate::Function, expr)
    if isdefined(expr, :args)
        for arg in expr.args
            if predicate(arg)
                return true
            end
            walkargs(predicate, arg)
        end
    end
    return false
end 

function reconstruct(info::Core.CodeInfo, func_name::Symbol)
    
    # Track which index the function signature can be found on
    sig_index = nothing

    # create a dictionary of statements
    statements = Dict{Core.SSAValue, Any}()
    assignments = Dict{Core.SlotNumber, Any}()

    # create a unique flag for each call to mark missing values
    NO_VALUES = gensym()

    function rebuild!(values::AbstractVector)
        return rebuild!.(values)
    end

    function rebuild!(expr::Expr)
        expr.args = rebuild!.(expr.args)
        return expr
    end

    function rebuild!(ssa::Core.SSAValue)
        return rebuild!(statements[ssa])
    end

    function rebuild!(slot::Core.SlotNumber)
        value = get(assignments, slot, NO_VALUES)
        return value == NO_VALUES ? slot : rebuild!(value)
    end

    function rebuild!(value::Any)
        return value
    end
    
    for (index, expr) in enumerate(info.code)

        ssa_index = Core.SSAValue(index)
        statements[ssa_index] = expr 

        if expr isa Expr
            if expr.head == :(=)
                (lhs, rhs) = expr.args  
                try
                    assignments[lhs] = eval(rebuild!(rhs))
                catch 
                end
                
            # identify the function signature
            elseif isdefined(expr, :args) && expr.head == :call
                for arg in expr.args
                    if arg isa Core.SlotNumber && arg.id == 1
                        sig_index = ssa_index
                    end
                end
            end
        end     
    end


    # exit early if no sig is found
    if isnothing(sig_index)
        # if there is not function signature, then we filter out the values directly
        return [arg for arg in info.code if !is_lowered(arg)]
    end 


    # Recursively build an expression of the actual type of each argument in the function signature
    evaled_sig = rebuild!(statements[sig_index])

    default_values = []

    for arg in evaled_sig.args

        contains_func_name = walkargs(arg) do x
            # Super generic check to see if the function name is in the expression
            return contains("$x", "$func_name")
        end

        if contains_func_name || arg == NO_VALUES  || arg isa GlobalRef && contains("$(arg.name)", "$func_name")
            continue            
        end

        if  arg isa Expr
            push!(default_values, eval(arg))
        else
            push!(default_values, arg)
        end
    end

    return default_values
end



"""
Return true if the given object is one of the types found in lowered IR code
Values were taken from here: https://docs.julialang.org/en/v1/devdocs/ast/#Lowered-form

I've purposely ignored the Core.GlobalRef type, because we can just lookup the underlying value at runtime
"""
function is_lowered(instance::Any) :: Bool
    return instance isa Union{
        Expr, Core.SlotNumber, Core.Argument, Core.CodeInfo, 
        Core.GotoNode, Core.GotoIfNot, Core.ReturnNode, Core.QuoteNode, 
        Core.SSAValue, Core.NewvarNode
    }
end



# """
# Returns true if the CodeInfo block has an expression where the first arg is a SlotNumber with id 1
# """
# function has_sig_expr(info::Core.CodeInfo) :: Bool
#     for expr in info.code
#         # identify the function signature
#         if isdefined(expr, :args) && expr.head == :call
#             first_arg = first(expr.args)
#             if first_arg isa Core.SlotNumber && first_arg.id == 1
#                 return true
#             end
#         end
#     end
#     return false
# end

function extract_defaults(info::Vector{Core.CodeInfo}, func_name::Symbol, param_names, kwarg_names; start=2)

    param_defaults = Dict()
    kwarg_defaults = Dict()

    for c in info

        # skip parsing function bodys which normally start with newvarnodes
        if first(c.code) isa Core.NewvarNode
            continue
        end

        sig_args = reconstruct(c, func_name)
        p_defaults, kw_defaults = splitargs(sig_args, func_name)

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

    return param_defaults, kwarg_defaults 
end


function splitdef(f::Function; start=1)

    # Convert to low level IR code
    info = Base.code_lowered(f)

    func_methods = methods(f)
    func_name = first(func_methods).name

    # Extract parameter names and types
    param_names, param_types, kwarg_names = getsignames(func_methods)

    # Extract default values
    param_defaults, kwarg_defaults = extract_defaults(info, func_name, param_names, kwarg_names)

    # Create a list of Param objects from parameters
    params = Vector{Param}()
    for (name, type) in zip(param_names, param_types)
        if haskey(param_defaults, name)
            # inferr the type of the parameter based on the default value
            param_default = param_defaults[name]
            inferred_type = type == Any ? typeof(param_default) : type
            push!(params, Param(name=name, type=inferred_type, default=param_default, hasdefault=true))
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

    sig_params = vcat(params, keyword_args)[start:end]

    return (
        name = func_name,
        args = params[start:end],
        kwargs = keyword_args[start:end],
        sig = sig_params,
        sig_map = Dict{Symbol,Param}(param.name => param for param in sig_params)
    )
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

function parsetype(target_type::Type{T}, value::Any) :: T where {T}
    if value isa T
        return value
    elseif value isa AbstractString
        return parse(target_type, value)
    else
        return convert(target_type, value)
    end
end

"""
    struct_builder(::Type{T}, parameters::Dict{String,String}) where {T}

Constructs an object of type `T` using the parameters in the dictionary `parameters`.
"""
function struct_builder(::Type{T}, params::AbstractDict) :: T where {T}
    has_kwdef = has_kwdef_constructor(T)
    params_with_symbols = Dict(Symbol(k) => v for (k, v) in params)   
    if has_kwdef
        # case 1: Use slower converter to handle structs with default values
        return kwarg_struct_builder(T, params_with_symbols)
    else
        # case 2: Use faster converter to handle structs with no defaults
        return StructTypes.constructfrom(T, params_with_symbols)
    end
end

"""
    kwarg_struct_builder(TargetType::Type{T}, params::AbstractDict) where {T}
"""
function kwarg_struct_builder(TargetType::Type{T}, params::AbstractDict) where {T}
    
    info = extract_struct_info(TargetType)
    param_dict = Dict{Symbol, Any}()

    for param_name in info.names

        # ignore unkown parameters
        if haskey(params, param_name)
            param_value = params[param_name]
            target_type = info.map[param_name]

            # Figure out how to parse the current param
            if target_type == Any || target_type == String
                parsed_value = param_value
            elseif isstructtype(target_type)
                parsed_value = struct_builder(target_type, param_value)
            else
                parsed_value = parsetype(target_type, param_value)
            end

            param_dict[param_name] = parsed_value
        end
    end
    
    return TargetType(;param_dict...)
end

end