# Schema generation, argument coercion/invocation, content blocks, and result
# helpers. Groups the four `serialization/` files under one namespace so tools,
# prompts, resources, and streams share one serialization contract.

module Serialization

using HTTP
using JSON
using Base64: base64encode

using ...AutoDoc
using ...Reflection
using ...AppContext: ServerContext
using ...Util: response_bytes
using ...Types: MCPParam, MCPTool, MCPCallable, isrequired
using ..Errors: MCPRequestError, MCP_INVALID_PARAMS, MCP_INTERNAL_ERROR, MCP_RESOURCE_NOT_FOUND, error_body, toolerror_result
using ..Specs: LATEST_LEGACY_SPEC, emits_structured_content, result_envelope, with_cache_hints

include("serialization/schema.jl")
include("serialization/registration.jl")
include("serialization/arguments.jl")
include("serialization/content.jl")
include("serialization/envelopes.jl")

end # module Serialization
