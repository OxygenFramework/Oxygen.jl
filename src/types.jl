module Types
"""
This module holds Structs that are used throughout the application
"""

using HTTP
using Sockets
using Dates
using DataStructures: CircularDeque

export Server, History, HTTPTransaction, TaggedRoute,
    WebRequest, Handler, Nullable, 
    ActiveTask, RegisteredTask, TaskDefinition,
    ActiveCron, RegisteredCron, CronDefinition

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

struct WebRequest
    http :: HTTP.Stream
    done :: Threads.Event
end

struct Handler
    queue   :: Channel{WebRequest}
    count   :: Threads.Atomic{Int}
    shutdown:: Threads.Atomic{Bool}

    Handler( queuesize = 1024 ) = begin
        new(Channel{WebRequest}(queuesize), Threads.Atomic{Int}(0), Threads.Atomic{Bool}(false))
    end
end

const Server = HTTP.Server
const History = CircularDeque{HTTPTransaction}

end