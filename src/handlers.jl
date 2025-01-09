module Handlers
using HTTP
using ..Types: Nullable
using ..Constants: SPECIAL_METHODS, TYPE_ALIASES
using ..AppContext: ServerContext
using BenchmarkTools
export select_handler, first_arg_type

# Union type of supported Handlers
HandlerArgType = Union{HTTP.Messages.Request, HTTP.WebSockets.WebSocket, HTTP.Streams.Stream}

""" 
Determine how to call each handler based on the arguments it takes.
"""
function get_invoker_stategy(has_ctx_kwarg::Bool, has_req_kwarg::Bool, has_path_params::Bool, no_args::Bool, ctx::ServerContext)
    if has_req_kwarg && has_ctx_kwarg
        if no_args
            return function (func::Function, _::HandlerArgType, req::HTTP.Messages.Request, _::Nullable{Vector})
                func(; request=req, context=ctx.app_context[])
            end
        elseif has_path_params
            return function (func::Function, arg::HandlerArgType, req::HTTP.Messages.Request, parameters::Nullable{Vector})
                func(arg, parameters...; request=req, context=ctx.app_context[])
            end
        else
            return function (func::Function, arg::HandlerArgType, req::HTTP.Messages.Request, _::Nullable{Vector})
                func(arg; request=req, context=ctx.app_context[])
            end
        end
    elseif has_req_kwarg
        if no_args
            return function (func::Function, _::HandlerArgType, req::HTTP.Messages.Request, _::Nullable{Vector})
                func(; request=req)
            end
        elseif has_path_params
            return function (func::Function, arg::HandlerArgType, req::HTTP.Messages.Request, parameters::Nullable{Vector})
                func(arg, parameters...; request=req)
            end
        else
            return function (func::Function, arg::HandlerArgType, req::HTTP.Messages.Request, _::Nullable{Vector})
                func(arg; request=req)
            end
        end
    elseif has_ctx_kwarg
        if no_args
            return function (func::Function, _::HandlerArgType, _::HTTP.Messages.Request, _::Nullable{Vector})
                func(; context=ctx.app_context[])
            end
        elseif has_path_params
            return function (func::Function, arg::HandlerArgType, _::HTTP.Messages.Request, parameters::Nullable{Vector})
                func(arg, parameters...; context=ctx.app_context[])
            end
        else
            return function (func::Function, arg::HandlerArgType, _::HTTP.Messages.Request, _::Nullable{Vector})
                func(arg; context=ctx.app_context[])
            end
        end
    else
        if no_args
            return function (func::Function, _::HandlerArgType, _::HTTP.Messages.Request, _::Nullable{Vector})
                func()
            end
        elseif has_path_params
            return function (func::Function, arg::HandlerArgType, _::HTTP.Messages.Request, parameters::Nullable{Vector})
                func(arg, parameters...)
            end
        else
            return function (func::Function, arg::HandlerArgType, _::HTTP.Messages.Request, _::Nullable{Vector})
                func(arg)
            end
        end
    end
end

# """
# Determine how to call each handler based on the arguments it takes.
# """
# function get_invoker_stategy(has_ctx_kwarg::Bool, has_req_kwarg::Bool, has_path_params::Bool, no_args::Bool, ctx::ServerContext)
#     function build_invoker(func, arg, req, parameters)
#         kwargs = Dict{Symbol, Any}()
#         if has_req_kwarg
#             kwargs[:request] = req
#         end
#         if has_ctx_kwarg
#             kwargs[:context] = ctx.app_context[]
#         end

#         if no_args
#             return func(; kwargs...)
#         elseif has_path_params
#             return func(arg, parameters...; kwargs...)
#         else
#             return func(arg; kwargs...)
#         end
#     end

#     return function (func::Function, arg::HandlerArgType, req::HTTP.Messages.Request, parameters::Nullable{Vector})
#         @btime $build_invoker($func, $arg, $req, $parameters)
#     end
# end


"""
    select_handler(::Type{T})

This base case, returns a handler for `HTTP.Request` objects.
"""
function select_handler(::Type{T}, has_ctx_kwarg::Bool, has_req_kwarg::Bool, has_path_params::Bool, ctx::ServerContext; no_args=false) where {T}
    invoker = get_invoker_stategy(has_ctx_kwarg, has_req_kwarg, has_path_params, no_args, ctx)
    function (req::HTTP.Request, func::Function; parameters::Nullable{Vector}=nothing)
        invoker(func, req, req, parameters)
    end
end

"""
    select_handler(::Type{HTTP.Streams.Stream})

Returns a handler for `HTTP.Streams.Stream` types
"""
function select_handler(::Type{HTTP.Streams.Stream}, has_ctx_kwarg::Bool, has_req_kwarg::Bool, has_path_params::Bool, ctx::ServerContext; no_args=false)
    invoker = get_invoker_stategy(has_ctx_kwarg, has_req_kwarg, has_path_params, no_args, ctx)
    function (req::HTTP.Request, func::Function; parameters::Nullable{Vector}=nothing)
        invoker(func, req.context[:stream], req, parameters)
    end
end

"""
    select_handler(::Type{HTTP.WebSockets.WebSocket})

Returns a handler for `HTTP.WebSockets.WebSocket`types
"""
function select_handler(::Type{HTTP.WebSockets.WebSocket}, has_ctx_kwarg::Bool, has_req_kwarg::Bool, has_path_params::Bool, ctx::ServerContext; no_args=false)
    invoker = get_invoker_stategy(has_ctx_kwarg, has_req_kwarg, has_path_params, no_args, ctx)
    function (req::HTTP.Request, func::Function; parameters::Nullable{Vector}=nothing)
        HTTP.WebSockets.isupgrade(req) && HTTP.WebSockets.upgrade(ws -> invoker(func, ws, req, parameters), req.context[:stream])
    end
end

"""
first_arg_type(method::Method, httpmethod::String)

Determine the type of the first argument of a given method.
If the `httpmethod` is in `Constants.SPECIAL_METHODS`, the function will return the 
corresponding type from `TYPE_ALIASES` if it exists, or `Type{HTTP.Request}` as a default.
Otherwise, it will return the type of the second field of the method's signature.
"""
function first_arg_type(method::Method, httpmethod::String) :: Type
    if httpmethod in SPECIAL_METHODS
        return get(TYPE_ALIASES, httpmethod, HTTP.Request)
    else
        # either grab the first argument type or default to HTTP.Request
        field_types = fieldtypes(method.sig)
        return length(field_types) < 2 ? HTTP.Request : field_types[2]
    end
end


end