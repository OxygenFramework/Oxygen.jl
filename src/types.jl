module Types
"""
This module holds Structs that are used throughout the application
"""

using HTTP
using Sockets
using Dates
using DataStructures: CircularDeque

export Server, History, HTTPTransaction, TaggedRoute, Nullable, 
    ActiveTask, RegisteredTask, TaskDefinition,
    ActiveCron, RegisteredCron, CronDefinition,
    Param, hasdefault, gettype

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

function gettype(param::Param{T}) :: Type{T} where T
    return T
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
    return param.hasdefault
end

end