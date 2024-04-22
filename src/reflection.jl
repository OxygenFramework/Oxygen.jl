module Reflection
using StructTypes
using Base: @kwdef
using ..Types

export parse_func_info, struct_builder, extract_struct_info

const IGNORED_TYPES = Set([Expr, Core.GotoNode, Core.SlotNumber, Core.NewvarNode, Core.GotoIfNot])

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
    sig = Vector{Symbol}()
    types = Vector{Type}()
    kwarg_names = Vector{Symbol}()

    # track position & types of parameters in the function signature
    positions = Dict{Symbol, Int}()
    for m in func_methods
        argnames = Base.method_argnames(m)[start:end]
        argtypes = fieldtypes(m.sig)[start:end]
        for (i, (argname, type)) in enumerate(zip(argnames, argtypes))
            if argname ∉ sig
                push!(sig, argname)
                push!(types, type)
                positions[argname] = i
            end
        end
        for kwarg in Base.kwarg_decl(m)
            if kwarg ∉ kwarg_names && kwarg != :...
                push!(kwarg_names, kwarg)
            end
        end
    end
    return sig, types, kwarg_names
end


"""
Parses the args in a Expr object and returns any positional and keyword default values

The args parameter is a vector that follows this shape like This
[
    function_name...,
    UnionTypes...,
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

-----------
[Symbol("#self#"), :req, :query, :header, :a, :b]

#2#3 : GlobalRef - Main.ErgonomicsDemo.var"##2#3"   - name of the function (between # characters)
wow : String - String                               - first kwarg 
3.5 : Float64 - Float64                             - second kwarg
_1 : Core.SlotNumber - Core.SlotNumber
_2 : Core.SlotNumber - Core.SlotNumber
_3 : Core.SlotNumber - Core.SlotNumber
_4 : Core.SlotNumber - Core.SlotNumber
_5 : Core.SlotNumber - Core.SlotNumber
_6 : Core.SlotNumber - Core.SlotNumber

-----------
[Symbol("#self#"), :req, :query, :header, :a]

_1 : Core.SlotNumber - Core.SlotNumber
_2 : Core.SlotNumber - Core.SlotNumber
_3 : Core.SlotNumber - Core.SlotNumber
_4 : Core.SlotNumber - Core.SlotNumber
_5 : Core.SlotNumber - Core.SlotNumber
10 : Int64 - Int64                          - nth positional param default

-----------
[Symbol("#self#"), :req, :query, :header]

_1 : Core.SlotNumber - Core.SlotNumber
_2 : Core.SlotNumber - Core.SlotNumber
_3 : Core.SlotNumber - Core.SlotNumber
_4 : Core.SlotNumber - Core.SlotNumber
5 : Int64 - Int64                           - n-1 positional param default
10 : Int64 - Int64                          - nth positional param default

-----------
[Symbol("#self#"), :req, :query]

Main.ErgonomicsDemo.Oxygen.Core.Extractors.Header : GlobalRef - UnionAll
Main.ErgonomicsDemo.Sample : GlobalRef - DataType
_1 : Core.SlotNumber - Core.SlotNumber
_2 : Core.SlotNumber - Core.SlotNumber
_3 : Core.SlotNumber - Core.SlotNumber
%1 : Core.SSAValue - Core.SSAValue          - The location of the UnionAll type defined above
5 : Int64 - Int64                           - n-1 positional param default
10 : Int64 - Int64                          - nth positional param default


-----------
[Symbol("#self#"), :req]

Main.ErgonomicsDemo.Oxygen.Core.Extractors.Query : GlobalRef - UnionAll
Main.ErgonomicsDemo.Sample : GlobalRef - DataType
Main.ErgonomicsDemo.Oxygen.Core.Extractors.Header : GlobalRef - UnionAll
Main.ErgonomicsDemo.Sample : GlobalRef - DataType
_1 : Core.SlotNumber - Core.SlotNumber
_2 : Core.SlotNumber - Core.SlotNumber
%1 : Core.SSAValue - Core.SSAValue          - The location of the n-1 UnionAll type defined above
%2 : Core.SSAValue - Core.SSAValue          - The location of the nth UnionAll type defined above
5 : Int64 - Int64                           - n-1 positional param default
10 : Int64 - Int64                          - nth positional param default
"""
function splitargs(args::Vector, func_name::Symbol)
    param_defaults = Vector{Any}()
    kwarg_defaults = Vector{Any}()
    encountered_slot = false

    for arg in args
        # check if this is a function name
        if arg isa Core.GlobalRef && startswith(String(arg.name), "$func_name#")
            continue
        elseif isa(arg, Core.SSAValue)
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


function spliton(vector::Vector{T}, predicate::Function) :: Tuple{Vector{T}, Vector{T}} where T
    a = Vector{T}()
    b = Vector{T}()
    seen_target = false
    for item in vector
        # skip all items that match the predicate
        if predicate(item)
            seen_target = true
            continue
        end
        if !seen_target 
            push!(a, item)
        else
            push!(b, item)
        end
    end
    return a, b
end

# function is_func_def(func_name::Symbol, first_arg) :: Bool
#     return first_arg isa Core.GlobalRef && startswith(String(first_arg.name), "#$func_name#")
# end

function extract_defaults(func_name::Symbol, info, param_names, kwarg_names)

    # store default values
    param_defaults = Dict()
    kwarg_defaults = Dict()

    for c in info
        # println("\n-----------")
        # println(c.slotnames)
        # temp_kwarg_defaults = []
        for expr in c.code

            if isdefined(expr, :args)
                first_arg = first(expr.args)

                # is_func_def = first_arg isa Core.GlobalRef && startswith(String(first_arg.name), "#$func_name#")
                # regular_expression = first_arg isa Core.SlotNumber || first_arg isa Core.GlobalRef

                # println("is func: ", is_func_def)

                if !(first_arg isa Core.SlotNumber || first_arg isa Core.GlobalRef)
                    continue
                else

                    println(">> ", c)
                    io = IOBuffer()
                    show(io, "text/plain", c)

                    println(">>IO: ", String(take!(io)))

                    a, b = spliton(expr.args, arg ->  isa(arg, Core.SlotNumber) || isa(arg, Core.SSAValue))
                    println(a)
                    println(b)
                    println()

                    # p_defaults, kw_defaults = splitargs(expr.args, func_name)
                    # # println("> param defaults: ", p_defaults)
                    # # println("> kwarg defaults: ", kw_defaults)


                    # # store the default values for params
                    # if !isempty(p_defaults)
                    #     # we reverse, because each subsequent expression should show more defaults,
                    #     # so we need to keep updating them as we see them.
                    #     for (name, value) in zip(reverse(param_names), reverse(p_defaults))
                    #         param_defaults[name] = value
                    #     end
                    # end

                    # # store the default values for kwargs
                    # if !isempty(kw_defaults)
                    #     for (name, value) in zip(kwarg_names, kw_defaults)
                    #         kwarg_defaults[name] = value
                    #     end
                    # end
                end
            else 
                continue
            end

            # for arg in expr.args 
            #     println(getargvalue(arg), " : ", typeof(arg), " - ", typeof(getargvalue(arg)))
            # end

            
            # # Here is a loop guard to skip expressions we don't care about
            # if isa(expr, Expr) && isdefined(expr, :args)
            #     first_arg = getargvalue(first(expr.args))

            #     # only work with function definition expressions and include (#self#)
            #     if !(first_arg isa Core.SlotNumber && first_arg.id == 1) && !(first_arg isa Core.GlobalRef)
            #         continue
            #     end
            # else

            #     continue
            # end

        


            # println(">> ", c)


         
            # """
            # If a kwarg has no default value it messes with the expr ordering, which means we 
            # need to extract it early and store it for later use. If we can parse default values
            # normally then the temp values won't get used.
            # """
            # if typeof(expr) ∉ IGNORED_TYPES
            #     push!(temp_kwarg_defaults, expr)
            #     continue
            # end


            # first_arg = first(expr.args)

            # """
            # 1.) skip any non expressions
            # 2.) skip any non call expressions
            # 3.) skip any Expr that doesn't have a slotnumber or structtype as the first arg
            # """
            # if !isa(expr, Expr) || expr.head != :call || !(isa(first_arg, Core.SlotNumber) || isstructtype(getargvalue(first_arg)))
            #     continue
            # end   

            # println(">> ", expr)
            # println("== ", getargvalue(first_arg))


            # get the default values for this expression
            # p_defaults, kw_defaults = splitargs(expr.args[2:end])


            # # store the default values for params
            # if !isempty(p_defaults)
            #     # we reverse, because each subsequent expression should show more defaults,
            #     # so we need to keep updating them as we see them.
            #     for (name, value) in zip(reverse(param_names), reverse(p_defaults))
            #         param_defaults[name] = value
            #     end
            # end

            # # store the default values for kwargs
            # if !isempty(kw_defaults)
            #     for (name, value) in zip(kwarg_names, kw_defaults)
            #         kwarg_defaults[name] = value
            #     end
            # end

        end

        # """
        # If we haven't found any defaults normally, then that means a kwarg has no default value
        # and is altering the structure of the expressions. When this happens use the temp kwarg values
        # parsed from early and insert these.
        # """
        # if isempty(kwarg_defaults) && !isempty(temp_kwarg_defaults)
        #     for (name, value) in zip(kwarg_names, temp_kwarg_defaults)
        #         kwarg_defaults[name] = value
        #     end
        # end

    end

    # println("> param defaults: ", param_defaults)
    # println("> kwarg defaults: ", kwarg_defaults)
    return param_defaults, kwarg_defaults

end


"""
1.) iterate through a top level expression
2.) If any SSA values are found, we lookup that statement, 
3.) If that statement has any SSA values, we lookup those statements
4.) We continue this process until we reach the end of the expression and evaluate it all

The net result should be a list of default values that correspond to the initial function signature
"""
function build_sig(expression::Expr, statements::Dict{Core.SSAValue, Any})

    # Create a list to store the default values
    default_values = []

    # Define a recursive function to handle the SSA values
    function handle_ssa(arg)
        if arg isa Core.SSAValue
            expr = statements[arg]

            # Replace the SSA values in the arguments with their corresponding expressions
            expr.args = [x isa Core.SSAValue ? statements[x] : x for x in expr.args]

            # Check if the expression has any SSA values
            has_ssa = !isempty(findall(x -> isa(x, Core.SSAValue), expr.args))

            # If the expression doesn't have any SSA values, evaluate it
            if !has_ssa
                # Evaluate the expression and push the result
                push!(default_values, eval(expr))
            else
                # If the expression has SSA values, handle them recursively
                for x in expr.args 
                    if isa(x, Core.SSAValue)
                        handle_ssa(x)
                    else
                        push!(default_values, x)
                    end
                end
            end
        else
            push!(default_values, arg)
        end
    end

    # Start the recursive process
    for arg in expression.args
        handle_ssa(arg)
    end

    return default_values
end


function readcodeinfo(info::Vector{Core.CodeInfo}, func_name::Symbol, param_names, kwarg_names, start=2)

    param_defaults = Dict()
    kwarg_defaults = Dict()

    for c in info
        sig_index = nothing

        # create a dictionary of statements
        statements = Dict{Core.SSAValue, Any}()
        for (index, expr) in enumerate(c.code)
            ssa_index = Core.SSAValue(index)
            # identify the function signature
            if isdefined(expr, :args) && expr.head == :call
                first_arg = first(expr.args) 
                if first_arg isa Core.SlotNumber && first_arg.id == 1
                    sig_index = ssa_index
                end
            end
            statements[ssa_index] = expr
        end

        if !isnothing(sig_index)
            sig_args = build_sig(statements[sig_index], statements)[start:end]
        else
            sig_args = first(c.code).args[start:end]
        end

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


function parse_func_info(f::Function, start=2)

    func_methods = methods(f)
    func_name = first(func_methods).name

    # Extract parameter names and types
    param_names, param_types, kwarg_names = getsignames(func_methods, start=start)

    # Convert to low level IR code
    info = Base.code_lowered(f)

    # Extract default values
    param_defaults, kwarg_defaults  = readcodeinfo(info, func_name, param_names, kwarg_names)


    # return

    # param_defaults, kwarg_defaults = extract_defaults(func_name, info, param_names, kwarg_names)

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
        name = func_name,
        args = params,
        kwargs = keyword_args,
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