# Result envelopes and JSON-RPC response helpers. `server_info` and
# `modern_envelope` live in `MCP.Envelopes` (they are shared by the spec
# strategies); this file keeps the result pipeline built on top of them.
# Included into `MCP.Serialization` by `../serialization.jl`.

# ----------------------------------------------------------------------------
# Result envelope
# ----------------------------------------------------------------------------

"""
    list_result(key, items; spec) :: Dict

Build a `*/list` result under `key` through the revision's result strategy: the
modern revision adds cache hints, legacy revisions leave the result untouched.
"""
function list_result(key::String, items::Vector{Dict{String,Any}};
                     spec::Val=LATEST_LEGACY_SPEC)::Dict{String,Any}
    return with_cache_hints(spec, Dict{String,Any}(key => items))
end

# ----------------------------------------------------------------------------
# JSON-RPC response helpers
# ----------------------------------------------------------------------------

# JSON-RPC response helper used by the buffered and streamed result paths
# alike. Transport-specific writers live in `../transports/io.jl` and
# `../transports/transport.jl`.
function result_body(id, result)::Dict{String,Any}
    return Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "result" => result)
end

"""
    result_response(ctx, id, result; spec) :: (body, status)

Shape `result` through the revision's envelope (a no-op for legacy revisions)
and wrap it in its JSON-RPC body. The single place the envelope is applied to
successful results.
"""
function result_response(ctx::ServerContext, id, result::Dict{String,Any};
                         spec::Val=LATEST_LEGACY_SPEC)::Tuple{Dict{String,Any},Int}
    return result_body(id, result_envelope(spec, ctx, result)), 200
end

"""
    request_error_body(id, error, code) :: Dict

The JSON-RPC error body for a thrown `MCPRequestError`, normally using the
error's own code. `read_resource` overrides the code to translate the legacy
not-found error by era.
"""
function request_error_body(id, error::MCPRequestError, code::Int=error.code)::Dict{String,Any}
    return error_body(id, code, error.message, error.data)
end
