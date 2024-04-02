module Constants
using HTTP
using RelocatableFolders

export DATA_PATH,
    GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE, 
    HTTP_METHODS,
    WEBSOCKET, STREAM,
    SPECIAL_METHODS, METHOD_ALIASES, TYPE_ALIASES

# Generate a reliable path to our internal data folder that works when the 
# package is used with PackageCompiler.jl
const DATA_PATH = @path abspath(joinpath(@__DIR__, "..", "data"))

# HTTP Methods
const GET       = "GET"
const POST      = "POST"
const PUT       = "PUT"
const DELETE    = "DELETE"
const PATCH     = "PATCH"
const HEAD      = "HEAD"
const OPTIONS   = "OPTIONS"
const CONNECT   = "CONNECT"
const TRACE     = "TRACE"

const HTTP_METHODS = Set{String}([GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE])

# Special Methods
const WEBSOCKET = "WEBSOCKET"
const STREAM    = "STREAM"

const SPECIAL_METHODS = Set{String}([WEBSOCKET, STREAM])

# Sepcial Method Aliases
const METHOD_ALIASES = Dict{String,String}(
    WEBSOCKET => GET,
    STREAM => GET
)

const TYPE_ALIASES = Dict{String, Type}(
    WEBSOCKET => HTTP.WebSockets.WebSocket,
    STREAM => HTTP.Streams.Stream
)

end