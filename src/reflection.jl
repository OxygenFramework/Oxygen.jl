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

        if arg isa Expr
            push!(default_values, eval(arg))
        else
            push!(default_values, arg)
        end
    end

    return default_values
end

"""
Returns true if the CodeInfo object has a function signature

Most funtion signatures follow this general pattern
- The second to last expression is used as the function signature
- The last argument is a Return node 

Below are a couple different examples of this in pattern in action:

# Standard function signature

CodeInfo(
1 ─ %1 = (#self#)(req, a, path, qparams, 23)
└──      return %1
)

# Extractor example (as a default value)

CodeInfo(
1 ─      #22 = %new(Main.RunTests.ExtractorTests.:(var"#22#37"))
│   %2 = #22
│   %3 = Main.RunTests.ExtractorTests.Header(Main.RunTests.ExtractorTests.Sample, %2)
│   %4 = (#self#)(req, %3)
└──      return %4
)

# This kind of function signature happens when a keyword argument is defined without at default value

CodeInfo(
1 ─ %1  = "default"
│         c = %1
│   %3  = true
│         d = %3
│   %5  = Core.UndefKeywordError(:request)
│   %6  = Core.throw(%5)
│         request = %6
│   %8  = Core.getfield(#self#, Symbol("#8#9"))
│   %9  = c
│   %10 = d
│   %11 = request
│   %12 = (%8)(%9, %10, %11, #self#, a, b)
└──       return %12
)
"""
function has_sig_expr(c::Core.CodeInfo) :: Bool

    statements_length = length(c.code)

    # prevent index out of bounds
    if statements_length < 2
        return false
    end

    # check for our pattern of a function signature followed by a return statement
    last_expr = c.code[statements_length]
    second_to_last_expr = c.code[statements_length - 1]
    
    if last_expr isa Core.ReturnNode && second_to_last_expr isa Expr && second_to_last_expr.head == :call
        # recursivley search expression to see if we have a SlotNumber(1) in the args
        return walkargs(second_to_last_expr) do arg
            return isa(arg, Core.SlotNumber) && arg.id == 1
        end    
    end

    return false
end

"""
Given a list of CodeInfo objects, extract any default values assigned to parameters & keyword arguments
"""
function extract_defaults(info::Vector{Core.CodeInfo}, func_name::Symbol, param_names::Vector{Symbol}, kwarg_names::Vector{Symbol})

    # These store the mapping between parameter names and their default values
    param_defaults = Dict()
    kwarg_defaults = Dict()

    # Given the params, we can take an educated guess and map the slot number to the parameter name
    slot_mapping = Dict(i + 1 => p for (i, p) in enumerate(vcat(param_names, kwarg_names)))

    # skip parsing if no parameters or keyword arguments are found
    if isempty(param_names) && isempty(kwarg_names)
        return param_defaults, kwarg_defaults 
    end

    for c in info

        # skip code info objects that don't have a function signature
        if !has_sig_expr(c)
            continue
        end

        # rebuild the function signature with the default values included
        sig_args = reconstruct(c, func_name)

        sig_length = length(sig_args)
        self_index = findfirst([isa(x, Core.SlotNumber) && x.id == 1 for x in sig_args])

        for (index, arg) in enumerate(sig_args)

            # for keyword arguments
            if index < self_index  

                # derive the current slot name
                slot_number = sig_length - abs(self_index - index) + 1
                slot_name = slot_mapping[slot_number]

                # don't store slot numbers when no default is given
                value = getargvalue(arg)
                if !isa(value, Core.SlotNumber)
                    kwarg_defaults[slot_name] = value
                end

            # for regular arguments
            elseif index > self_index 
                  
                # derive the current slot name
                slot_number = abs(self_index - index) + 1
                slot_name = slot_mapping[slot_number]

                # don't store slot numbers when no default is given
                value = getargvalue(arg)
                if !isa(value, Core.SlotNumber)
                    param_defaults[slot_name] = value
                end
            end

        end
    end 

    return param_defaults, kwarg_defaults 
end


# Return the more specific type
function select_type(t1::Type, t2::Type)
    # case 1: only t1 is any
    if t1 == Any && t2 != Any
        return t2

    # case 2: only t2 is any
    elseif t2 == Any && t1 != Any
        return t1

    # case 3: Niether / Both types are Any, chose the more specific type
    else
        if t1 <: t2
            return t1
        elseif t2 <: t1
            return t2
        else
            # if the types are the same, return the first type
            return t1
        end
    end
end

# Merge two parameter objects, defaultint to the original params value
function mergeparams(p1::Param, p2::Param) :: Param
    return Param(
        name    = p1.name,
        type    = select_type(p1.type, p2.type),
        default = coalesce(p1.default, p2.default),
        hasdefault = p1.hasdefault || p2.hasdefault
    )
end


"""
Used to extract the function signature from regular Julia functions.
"""
function splitdef(f::Function; start=1)
    method_defs = methods(f)
    func_name = first(method_defs).name
    return splitdef(Base.code_lowered(f), methods(f), func_name, start=start)
end


"""
Used to extract the function signature from regular Julia Structs.
This function merges the signature map at the end, because it's common
for structs to have multiple constructors with the same parameter names as both
keyword args and regular args.
"""
function splitdef(t::DataType; start=1)
    results = splitdef(Base.code_lowered(t), methods(t), nameof(t), start=start)
    sig_map = Dict{Symbol,Param}()
    for param in results.sig
        # merge parameters with the same name
        if haskey(sig_map, param.name)
            sig_map[param.name] = mergeparams(sig_map[param.name], param)
        # add unique parameter to the map
        else
            sig_map[param.name] = param
        end
    end
    merge!(results.sig_map, sig_map)
    return results
end


function splitdef(info::Vector{Core.CodeInfo}, method_defs::Base.MethodList, func_name::Symbol; start=1)

    # Extract parameter names and types
    param_names, param_types, kwarg_names = getsignames(method_defs)

    # Extract default values
    param_defaults, kwarg_defaults = extract_defaults(info, func_name, param_names, kwarg_names)

    # Create a list of Param objects from parameters
    params = Vector{Param}()
    for (name, type) in zip(param_names, param_types)
        if haskey(param_defaults, name)
            # inferr the type of the parameter based on the default value
            param_default = param_defaults[name]
            inferred_type = type == Any ? typeof(param_default) : type
            if typeof(param_default) == inferred_type
                push!(params, Param(name=name, type=inferred_type, default=param_default, hasdefault=true))
            else
                @warn "splitdef: Default for $func_name.$name type ($(typeof(param_default))) differs from inferred type ($inferred_type). Skipping."
                push!(params, Param(name=name, type=type))
            end
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