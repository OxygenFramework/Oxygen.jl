module Types
"""
This module holds Structs that are used throughout the application
"""

using HTTP
using Sockets
using JSON3
using Dates
using Base: @kwdef
using DataStructures: CircularDeque
using ..Util

export Server, History, HTTPTransaction, TaggedRoute, Nullable, 
    ActiveTask, RegisteredTask, TaskDefinition,
    ActiveCron, RegisteredCron, CronDefinition,
    Param, LazyRequest, headers, pathparams, queryvars, jsonbody, formbody, textbody

const Nullable{T} = Union{T, Nothing}

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

const Server = HTTP.Server
const History = CircularDeque{HTTPTransaction}

@kwdef struct Param{T}
    name::Symbol
    type::Type{T}
    default::Union{T, Missing} = missing
    hasdefault::Bool = false
end


# Lazily init frequently used components of a request to be used between parameters when parsing
@kwdef struct LazyRequest
    request     :: HTTP.Request
    headers     = Ref{Nullable{Dict{String,String}}}(nothing)
    pathparams  = Ref{Nullable{Dict{String,String}}}(nothing)
    queryparams = Ref{Nullable{Dict{String,String}}}(nothing)
    formbody    = Ref{Nullable{Dict{String,String}}}(nothing)
    jsonbody    = Ref{Nullable{JSON3.Object}}(nothing)
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
        req.queryparams[] = Util.queryparams(req.request)
    end
    return req.queryparams[]
end

function jsonbody(req::LazyRequest) :: Nullable{JSON3.Object}
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