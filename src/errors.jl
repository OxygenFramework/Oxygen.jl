module Errors
## In this module, we export commonly used exceptions across the package 

export ValidationError, MCPRequestError,
    MCP_PARSE_ERROR, MCP_INVALID_REQUEST, MCP_METHOD_NOT_FOUND,
    MCP_INVALID_PARAMS, MCP_INTERNAL_ERROR, MCP_HEADER_MISMATCH,
    MCP_MISSING_REQUIRED_CLIENT_CAPABILITY, MCP_UNSUPPORTED_PROTOCOL_VERSION

# This is used by the Extractors.jl module to signal that a validation error has occurred
struct ValidationError <: Exception
    msg::String
    cause::Union{Nothing, Exception}
    ValidationError(msg::String) = new(msg, nothing)
    ValidationError(msg::String, cause::Exception) = new(msg, cause)
end

function Base.showerror(io::IO, e::ValidationError)
    print(io, "Validation Error: $(e.msg)")
    if !isnothing(e.cause)
        print(io, "\nCaused by: ")
        showerror(io, e.cause)
    end
end

# Thrown while processing an MCP request to signal a JSON-RPC protocol error
struct MCPRequestError <: Exception
    code    :: Int
    message :: String
    data    :: Any
    MCPRequestError(code::Int, message::String) = new(code, message, nothing)
    MCPRequestError(code::Int, message::String, data) = new(code, message, data)
end

function Base.showerror(io::IO, e::MCPRequestError)
    print(io, "MCP Request Error ($(e.code)): $(e.message)")
end

# JSON-RPC 2.0 error codes used by the MCP transport
const MCP_PARSE_ERROR      :: Int = -32700
const MCP_INVALID_REQUEST  :: Int = -32600
const MCP_METHOD_NOT_FOUND :: Int = -32601
const MCP_INVALID_PARAMS   :: Int = -32602
const MCP_INTERNAL_ERROR   :: Int = -32603

# MCP transport error codes (JSON-RPC server error range)
const MCP_HEADER_MISMATCH                        :: Int = -32020
const MCP_MISSING_REQUIRED_CLIENT_CAPABILITY     :: Int = -32021
const MCP_UNSUPPORTED_PROTOCOL_VERSION           :: Int = -32022

end
