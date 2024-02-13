module Types
"""
This module holds Structs that are used throughout the application
"""

using HTTP
using Sockets
using Dates
using DataStructures: CircularDeque

export Server, History, HTTPTransaction, TaggedRoute

struct TaggedRoute 
    httpmethods::Vector{String} 
    tags::Vector{String}
end

struct HTTPTransaction
    # Intristic Properties
    ip::String
    uri::String
    timestamp::DateTime

    # derived properties
    duration::Float64
    success::Bool
    status::Int16
    error_message::Union{String,Nothing}
end

const Server    = HTTP.Server
const History   = CircularDeque{HTTPTransaction}


end