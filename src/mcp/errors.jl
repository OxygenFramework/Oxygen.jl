# JSON-RPC error codes and result helpers shared by the protocol and transport
# layers. Included into the `MCP` facade by `../mcp.jl`.

module Errors

export MCPRequestError, MCP_INVALID_PARAMS, MCP_RESOURCE_NOT_FOUND

"""
    MCPRequestError(code, message, data=nothing)

An error raised while processing an MCP request. It carries the JSON-RPC error
`code`, the client-facing `message`, and optional structured `data`; the
transport turns it into an error response.
"""
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

# Resource-not-found, per the legacy resources spec. The modern revision folded
# this case into `MCP_INVALID_PARAMS` (-32602); `read_resource` picks by era.
const MCP_RESOURCE_NOT_FOUND                     :: Int = -32002

function toolerror_result(error) :: Dict{String,Any}
    return Dict{String,Any}(
        "content" => [Dict{String,Any}("type" => "text", "text" => sprint(showerror, error))],
        "isError" => true,
    )
end

function error_body(id, code::Int, message::String, data=nothing) :: Dict{String,Any}
    error_object = Dict{String,Any}("code" => code, "message" => message)
    if !isnothing(data)
        error_object["data"] = data
    end
    return Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "error" => error_object)
end

# The modern-era per-request contract (`validate_modern_request`) is a revision
# delta and lives in `specs/behaviors.jl`. Request-specific header helpers
# live in `MCP.Headers`.

end # module Errors
