module Types
"""
This module holds Structs that are used throughout the application
"""

using HTTP
using Sockets
using JSON
using Dates
using Base: @kwdef
using DataStructures: CircularDeque
using ..Util

export Server, History, HTTPTransaction, TaggedRoute, Nullable, Context,
    ActiveTask, RegisteredTask, TaskDefinition,
    ActiveCron, RegisteredCron, CronDefinition,
    LifecycleMiddleware, startup, shutdown,
    Param, isrequired, LazyRequest, headers, pathparams, queryvars, jsonbody, formbody, textbody

const Nullable{T} = Union{T, Nothing}

# Represents the application context 
struct Context{T}
    payload::T
end

# Represents a running task
struct ActiveTask
    id      :: UInt
    timer   :: Timer
end

struct RegisteredTask
    id      :: UInt
    name    :: String
    interval:: Real
    action  :: Function
end

# A task defined through the router() HOF
struct TaskDefinition
    path        :: String
    httpmethod  :: String
    interval    :: Real
end

# A cron job defined through the router() HOF
struct CronDefinition
    path        :: String
    httpmethod  :: String
    expression  :: String
end

struct RegisteredCron
    id          :: UInt
    expression  :: String
    name        :: String
    action      :: Function
end

# Represents a running cron job
struct ActiveCron
    id        :: UInt
    job       :: RegisteredCron
end

struct TaggedRoute 
    httpmethods :: Vector{String} 
    tags        :: Vector{String}
end

struct HTTPTransaction
    # Intristic Properties
    ip          :: String
    uri         :: String
    timestamp   :: DateTime

    # derived properties
    duration    :: Float64
    success     :: Bool
    status      :: Int16
    error_message :: Nullable{String}
end

@kwdef struct LifecycleMiddleware 
    # The middleware function itself (handles incoming requests)
    middleware :: Function
    # A hook that's called when the server starts up (optional)
    on_startup :: Union{Function,Nothing} = nothing
    # A hook that's called when the server is shutdown (optional)
    on_shutdown :: Union{Function,Nothing} = nothing
end

function startup(lf::LifecycleMiddleware)
    if !isnothing(lf.on_startup)
        try 
            lf.on_startup()
        catch error
            @error "Error in LifecycleMiddleware.on_startup: " exception=(error, catch_backtrace())
        end
    end
end

function shutdown(lf::LifecycleMiddleware)
    if !isnothing(lf.on_shutdown)
        try
            lf.on_shutdown()
        catch error
            @error "Error in LifecycleMiddleware.on_shutdown: " exception=(error, catch_backtrace())
        end
    end
end

const Server = HTTP.Server
const History = CircularDeque{HTTPTransaction}

@kwdef struct Param{T}
    name::Symbol
    type::Type{T}
    default::Union{T, Missing} = missing
    hasdefault::Bool = false
end

function isrequired(p::Param{T}) where T
    return !p.hasdefault || (ismissing(p.default) && !(T <: Missing))
end

# Lazily init frequently used components of a request to be used between parameters when parsing
@kwdef struct LazyRequest
    request     :: HTTP.Request
    headers     = Ref{Nullable{Dict{String,String}}}(nothing)
    pathparams  = Ref{Nullable{Dict{String,String}}}(nothing)
    queryparams = Ref{Nullable{Dict{String,String}}}(nothing)
    formbody    = Ref{Nullable{Dict{String,String}}}(nothing)
    jsonbody    = Ref{Nullable{JSON.Object}}(nothing)
    textbody    = Ref{Nullable{String}}(nothing)
end

function headers(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.headers[])
        req.headers[] = Dict(String(k) => String(v) for (k,v) in HTTP.headers(req.request))
    end
    return req.headers[] 
end

function pathparams(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.pathparams[])
        req.pathparams[] = HTTP.getparams(req.request)
    end
    return req.pathparams[] 
end

function queryvars(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.queryparams[])
        req.queryparams[] = HTTP.queryparams(req.request)
    end
    return req.queryparams[]
end

function jsonbody(req::LazyRequest) :: Nullable{JSON.Object}
    if isnothing(req.jsonbody[])
        req.jsonbody[] = json(req.request)
    end
    return req.jsonbody[] 
end

function formbody(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.formbody[])
        req.formbody[] = formdata(req.request)
    end
    return req.formbody[] 
end

function textbody(req::LazyRequest) :: Nullable{String}
    if isnothing(req.textbody[])
        req.textbody[] = text(req.request)
    end
    return req.textbody[] 
end

end