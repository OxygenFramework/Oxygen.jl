# JSON-RPC method dispatch, envelope validation, and protocol-revision
# resolution. This is the shared dispatch contract: the generic `handle_method`
# lives here, and each domain module extends it explicitly with
# `import ..Dispatch: handle_method`.

module Dispatch

using HTTP

using ...AppContext: ServerContext

using ..Errors: error_body, MCP_METHOD_NOT_FOUND, MCP_INVALID_REQUEST
using ..Envelopes: META_KEY, META_PROTOCOL
using ..Headers: mcp_standard_header
using ..Specs: LATEST_LEGACY_SPEC, LATEST_MODERN_SPEC, is_modern, method_available, spec_from_version, spec_or_latest_legacy
using ..Sessions: MCPSession, legacy_version

# ----------------------------------------------------------------------------
# Envelope validation and message classification
# ----------------------------------------------------------------------------

# The `params` object of a request, empty when absent or not an object.
function request_params(payload) :: AbstractDict
    params = get(payload, "params", Dict{String,Any}())
    return params isa AbstractDict ? params : Dict{String,Any}()
end

# Classify a parsed JSON-RPC message by shape: request (method + id),
# notification (method, no id), client response (result/error + id, no method),
# or invalid. Returns a Symbol.
function message_shape(payload) :: Symbol
    if !(payload isa AbstractDict)
        return :invalid
    end
    has_method = haskey(payload, "method")
    has_id = haskey(payload, "id") && !isnothing(payload["id"])
    if has_method
        return has_id ? :request : :notification
    end
    if has_id && (haskey(payload, "result") || haskey(payload, "error"))
        return :client_response
    end
    return :invalid
end

"""
    validate_envelope(payload) :: Union{Nothing,Dict}

Enforce the JSON-RPC 2.0 envelope MCP requires: `jsonrpc` must be exactly
`"2.0"`, `method` must be a string, and an `id` may only be a string or a
number (a null id is forbidden by the MCP schema). Returns an error body, or
`nothing` when the envelope is well formed.
"""
function validate_envelope(payload) :: Union{Nothing,Dict{String,Any}}
    version = get(payload, "jsonrpc", nothing)
    if !(version isa AbstractString) || String(version) != "2.0"
        return error_body(get(payload, "id", nothing), MCP_INVALID_REQUEST,
                          "Invalid Request: jsonrpc must be exactly \"2.0\"")
    end

    method = get(payload, "method", nothing)
    if !(method isa AbstractString)
        return error_body(get(payload, "id", nothing), MCP_INVALID_REQUEST, "Invalid Request")
    end

    if haskey(payload, "id")
        id = payload["id"]
        if !(id isa AbstractString || (id isa Integer && !(id isa Bool)))
            return error_body(nothing, MCP_INVALID_REQUEST,
                              "Invalid Request: id must be a string or a number")
        end
    end
    return nothing
end

# ----------------------------------------------------------------------------
# Era claim and spec resolution
# ----------------------------------------------------------------------------

"""
    request_claim(req, method, params) :: Union{Nothing,Val,Symbol}

The modern-era claim of a request, before the session's negotiated version is
consulted. Returns the claimed `Val` revision when `params._meta` names a
supported modern revision, the method is `server/discover` (modern-only), or
(over HTTP) the `MCP-Protocol-Version` header names a modern revision.
`:unsupported` is returned when `_meta.protocolVersion` is a string naming a
revision this server cannot serve as a modern request; `nothing` means the
request claims nothing modern (a legacy request). See `request_spec` for the
claim combined with the negotiated legacy fallback.
"""
function request_claim(req::Union{Nothing,HTTP.Request}, method::String, params)
    meta = get(params, META_KEY, nothing)
    if meta isa AbstractDict
        version = get(meta, META_PROTOCOL, nothing)
        if version isa AbstractString
            spec = spec_from_version(String(version))
            return (!isnothing(spec) && is_modern(spec)) ? spec : :unsupported
        end
    end

    if method == "server/discover"
        return LATEST_MODERN_SPEC
    end

    if req isa HTTP.Request
        header_version = mcp_standard_header(req, "MCP-Protocol-Version")
        if header_version isa String
            header_spec = spec_from_version(strip(header_version))
            if !isnothing(header_spec) && is_modern(header_spec)
                return header_spec
            end
        end
    end

    return nothing
end

# The revision a legacy request runs under: parse the negotiated wire version
# on demand. Sessions (and the anonymous state on `MCPContext`, which predates
# this module) keep wire strings, so the `Val` never enters the context.
legacy_spec(ctx::ServerContext, session::Union{Nothing,MCPSession}) :: Val =
    spec_or_latest_legacy(legacy_version(ctx, session))

"""
    request_spec(ctx, req, method, params; session) :: Union{Nothing,Val}

The protocol revision a request runs under. A modern claim (see
`request_claim`) names its own revision; a legacy request falls back to the
session's negotiated version. Returns `nothing` when the request claims a
modern revision this server cannot serve; the caller answers `-32022`.
"""
function request_spec(
    ctx::ServerContext,
    req::Union{Nothing,HTTP.Request},
    method::String,
    params;
    session::Union{Nothing,MCPSession}=nothing)

    claim = request_claim(req, method, params)
    if isnothing(claim)
        return legacy_spec(ctx, session)
    end
    return claim isa Val ? claim : nothing
end

"""
    transport_spec(ctx, req, payload=nothing) :: Val

The revision governing transport policy for a request, resolved before
`process` determines the revision it dispatches under (see `request_spec`). A
modern claim (supported or not, because an unsupported one is answered
`-32022` before any session matters) classifies as the latest modern revision;
a legacy request falls back to the legacy revision negotiated on the context.
Only the policy interface (`uses_sessions`, `get_policy`, `delete_policy`) may
be asked of the result; it is a classification, not the request's revision.
"""
function transport_spec(ctx::ServerContext, req::HTTP.Request, payload=nothing) :: Val
    method = ""
    params = Dict{String,Any}()
    if payload isa AbstractDict
        name = get(payload, "method", nothing)
        if name isa AbstractString
            method = String(name)
        end
        params = request_params(payload)
    end

    claim = request_claim(req, method, params)
    if isnothing(claim)
        return legacy_spec(ctx, nothing)
    end
    return claim isa Val ? claim : LATEST_MODERN_SPEC
end

# ----------------------------------------------------------------------------
# Method table and dispatch
# ----------------------------------------------------------------------------

const METHOD_TAGS = Dict{String,Val}(
    "initialize" => Val(:initialize),
    "server/discover" => Val(:server_discover),
    "ping" => Val(:ping),
    "tools/list" => Val(:tools_list),
    "tools/call" => Val(:tools_call),
    "prompts/list" => Val(:prompts_list),
    "prompts/get" => Val(:prompts_get),
    "resources/list" => Val(:resources_list),
    "resources/templates/list" => Val(:resources_templates_list),
    "resources/read" => Val(:resources_read),
    "resources/subscribe" => Val(:resources_subscribe),
    "resources/unsubscribe" => Val(:resources_unsubscribe),
    "subscriptions/listen" => Val(:subscriptions_listen),
)

"""
    method_val(method) :: Val

Map a wire method name to its implementation tag. Unknown method names map to
`Val(:unknown)`, which the fallback `handle_method` answers with `-32601`.
"""
method_val(method::String) = get(METHOD_TAGS, method, Val(:unknown))

# Transport agnostic dispatch. Returns the JSON-RPC response body together with
# the HTTP status code that should be used for it (stdio ignores the status).
# A streamed `tools/call` returns its `StreamedCall` and a `subscriptions/listen`
# returns its `ListenCall`; the transport consumes those directly. The concrete
# return type is intentionally not annotated: `Dispatch` must not depend on
# `MCP.Streams` or `MCP.Subscriptions`. `spec` is the request's protocol revision
# (see `request_spec`); every method result is shaped through that revision's
# strategy.
#
# Routing is two dispatches on the method tag: `method_available` decides whether
# the active revision serves the method at all (an era-exclusive method answers
# `-32601` on the other era), then `handle_method` selects its one implementation,
# which lives with its domain (tools, prompts, resources, subscriptions).
function dispatch(
    ctx::ServerContext,
    req::Union{Nothing,HTTP.Request},
    id,
    method::String,
    payload;
    spec::Val=LATEST_LEGACY_SPEC,
    session::Union{Nothing,MCPSession}=nothing)

    tag = method_val(method)
    if !method_available(spec, tag)
        return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $method"), 404
    end
    return handle_method(spec, tag, ctx, req, id, request_params(payload), method; session=session)
end

# The fallback for an unknown wire method (and for a tag with no handler, were
# one ever added to `method_val` without an implementation). `raw` is the wire
# method name, reported verbatim.
function handle_method(
    spec::Val,
    tag::Val,
    ctx::ServerContext,
    req::Union{Nothing,HTTP.Request},
    id,
    params,
    raw::String;
    session::Union{Nothing,MCPSession}=nothing)

    return error_body(id, MCP_METHOD_NOT_FOUND, "Unknown method: $raw"), 404
end

end # module Dispatch
