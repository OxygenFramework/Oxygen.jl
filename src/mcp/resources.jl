# Resource registration, URI templates, content normalization, folder-backed
# resources, and the `resources/*` methods. Groups the five `resources/` files
# under one namespace.

module Resources

using HTTP
using JSON
using Base64: base64encode

using ...AppContext: ServerContext
using ...Types: Nullable, MCPParam, MCPResource
using ...Util: response_bytes

using ..Errors: MCPRequestError, MCP_INVALID_PARAMS, MCP_INTERNAL_ERROR, MCP_RESOURCE_NOT_FOUND, error_body
using ..Notifications: notify_change

using ..Serialization: string_keyed, is_text_mime, response_mime,
    reflect_handler, function_docstring, invoke_registered,
    list_result, result_response, request_error_body

using ..Specs: LATEST_LEGACY_SPEC, shows_resource_icons, not_found_code, with_cache_hints

import ..Dispatch: handle_method

export register_resource!, register_resource_folder!

include("resources/templates.jl")
include("resources/registration.jl")
include("resources/content.jl")
include("resources/methods.jl")
include("resources/folders.jl")

end # module Resources
