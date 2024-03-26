module Handlers
using HTTP
using ..Types: Nullable
using ..Core: SPECIAL_METHODS, TYPE_ALIASES

export select_handler, first_arg_type

# Union type of supported Handlers
HandlerArgType = Union{HTTP.Messages.Request, HTTP.WebSockets.WebSocket, HTTP.Streams.Stream}

""" 
Determine how to call each handler based on the arguments it takes.
"""
function get_invoker_stategy(has_req_kwarg::Bool, has_path_params::Bool, no_args::Bool)
    if has_req_kwarg
        if no_args
            return function (func::Function, _::HandlerArgType, req::HTTP.Messages.Request, _::Nullable{Vector})
                func(; request=req)
            end
        elseif has_path_params
            return function (func::Function, arg::HandlerArgType, req::HTTP.Messages.Request, pathParams::Nullable{Vector})
                func(arg, pathParams...; request=req)
            end
        else
            return function (func::Function, arg::HandlerArgType, req::HTTP.Messages.Request, _::Nullable{Vector})
                func(arg; request=req)
            end
        end
    else
        if no_args
            return function (func::Function, _::HandlerArgType, _::HTTP.Messages.Request, _::Nullable{Vector})
                func()
            end
        elseif has_path_params
            return function (func::Function, arg::HandlerArgType, _::HTTP.Messages.Request, pathParams::Nullable{Vector})
                func(arg, pathParams...)
            end
        else
            return function (func::Function, arg::HandlerArgType, _::HTTP.Messages.Request, _::Nullable{Vector})
                func(arg)
            end
        end
    end
end

"""
    select_handler(::Type{T})

This base case, returns a handler for `HTTP.Request` objects.
"""
function select_handler(::Type{T}, has_req_kwarg::Bool, has_path_params::Bool; no_args=false) where {T}
    invoker = get_invoker_stategy(has_req_kwarg, has_path_params, no_args)
    function (req::HTTP.Request, func::Function; pathParams::Nullable{Vector}=nothing)
        invoker(func, req, req, pathParams)
    end
end

"""
    select_handler(::Type{HTTP.Streams.Stream})

Returns a handler for `HTTP.Streams.Stream` types
"""
function select_handler(::Type{HTTP.Streams.Stream}, has_req_kwarg::Bool, has_path_params::Bool; no_args=false)
    invoker = get_invoker_stategy(has_req_kwarg, has_path_params, no_args)
    function (req::HTTP.Request, func::Function; pathParams::Nullable{Vector}=nothing)
        invoker(func, req.context[:stream], req, pathParams)
    end
end

"""
    select_handler(::Type{HTTP.WebSockets.WebSocket})

Returns a handler for `HTTP.WebSockets.WebSocket`types
"""
function select_handler(::Type{HTTP.WebSockets.WebSocket}, has_req_kwarg::Bool, has_path_params::Bool; no_args=false)
    invoker = get_invoker_stategy(has_req_kwarg, has_path_params, no_args)
    function (req::HTTP.Request, func::Function; pathParams::Nullable{Vector}=nothing)
        HTTP.WebSockets.isupgrade(req) && HTTP.WebSockets.upgrade(ws -> invoker(func, ws, req, pathParams), req.context[:stream])
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