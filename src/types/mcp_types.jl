module MCPTypes

using Base: @kwdef
using ..CoreTypes: Param, Nullable

export MCPConfig, MCPMetadata, MCPParam, MCPTool, MCPPrompt

"""
    MCPConfig

Metadata describing how a route (or a group of routes) is exposed over MCP.

The same struct is used at the router and route level so values can be inherited
and combined:

- `enabled`: whether the route is exposed as an MCP tool. Normalized metadata
  (`mcp = (...)`/`mcp = true`) is always enabled; `mcp = false` produces an
  explicitly disabled config.
- `description`: endpoint-specific text. At the router level this acts as a group
  prefix that is prepended to the route's own description.
- `group`: the inherited prefix from the enclosing router (populated while
  resolving, not parsed directly from user metadata).
- `parameters`: parameter name => human readable description.
- `names`: parameter name => MCP wire name. Lets a Julia parameter be exposed
  under a different JSON key.
- `toolname`: optional override for the tool's wire name (route level only).
"""
@kwdef struct MCPConfig
    enabled     :: Bool                = true
    description :: String              = ""
    group       :: String              = ""
    parameters  :: Dict{Symbol,String} = Dict{Symbol,String}()
    names       :: Dict{Symbol,String} = Dict{Symbol,String}()
    toolname    :: Nullable{String}    = nothing
end

# The raw `mcp` metadata forms accepted by `router()` and route registration:
# `false` to disable, `true`/a description `String`, or a `NamedTuple`/`Dict` of
# overrides. Kept as a union so the public HOF router signatures are strongly
# typed instead of implicitly `Any`; wrap it in `Nullable` for the optional
# (default `nothing`) case.
const MCPMetadata = Union{Bool, AbstractString, NamedTuple, AbstractDict}

# A single tool parameter paired with its explicit (human readable) description
# and the MCP wire name used on the JSON schema / invocation boundary.
struct MCPParam
    param       :: Param
    description :: String
    wirename    :: String
end

# Keeps the common case (wire name mirrors the Julia parameter name) terse.
MCPParam(param::Param, description::AbstractString) = MCPParam(param, String(description), string(param.name))

# A registered MCP tool. `params` contains the positional arguments (in order)
# followed by the keyword arguments. `argnames` identifies which parameters are
# positional so handlers can be invoked correctly.
struct MCPTool
    name        :: String
    description :: String
    handler     :: Function
    params      :: Vector{MCPParam}
    argnames    :: Vector{Symbol}
    has_context :: Bool          # handler wants `context` injected
    has_request :: Bool          # handler wants `request` injected
    inject_request :: Bool       # route tool: `request` is the leading positional arg
end

# A registered MCP prompt. The prompt arguments are the handler's own parameters
# (minus `context`/`request`), so the signature doubles as the template variable
# list. `argnames` identifies which parameters are positional.
struct MCPPrompt
    name        :: String
    description :: String
    handler     :: Function
    params      :: Vector{MCPParam}
    argnames    :: Vector{Symbol}
    has_context :: Bool          # handler wants `context` injected
    has_request :: Bool          # handler wants `request` injected
end

end
