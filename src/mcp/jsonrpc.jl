# JSON-RPC single-message processing, unsupported-version responses, and batch
# handling. Included into `MCP` by the `MCP.JSONRPC` submodule file.

module JSONRPC

using HTTP

using ...AppContext: ServerContext
using ...Streaming: cancel_stream!, drain_stream!

using ..Dispatch: dispatch, request_spec, request_params, message_shape, validate_envelope, request_claim, legacy_spec
using ..Envelopes: META_KEY, META_PROTOCOL
using ..Errors: MCPRequestError, MCP_INVALID_REQUEST, MCP_UNSUPPORTED_PROTOCOL_VERSION, error_body
using ..Sessions: MCPSession, mark_initialized!
using ..Serialization: request_error_body
using ..Specs: validate_request, SUPPORTED_VERSIONS, allows_batch, version_string, V2025_03_26
using ..Streams: StreamedCall, streamed_body
using ..Subscriptions: ListenCall, cancel_listen!

# Handle a single parsed JSON-RPC message. Returns `(body, status)`, where
# `body` is `nothing` for notifications and client responses (no response is
# written), a `StreamedCall` for a streamed tools/call, a `ListenCall` for a
# `subscriptions/listen` stream, or a JSON-RPC body. `session` carries the
# legacy Streamable HTTP session resolved by the transport, when any.
function process(ctx::ServerContext, payload, req::Union{Nothing,HTTP.Request};
                 session::Union{Nothing,MCPSession}=nothing)::Tuple{Union{Nothing,Dict{String,Any},StreamedCall,ListenCall},Int}
    shape = message_shape(payload)

    if shape === :invalid
        id = payload isa AbstractDict ? get(payload, "id", nothing) : nothing
        return error_body(id, MCP_INVALID_REQUEST, "Invalid Request"), 400
    end

    if shape === :client_response
        # The server sends no server-to-client requests, so acknowledge and drop.
        return nothing, 202
    end

    envelope = validate_envelope(payload)
    if !isnothing(envelope)
        return envelope, 400
    end

    method = payload["method"]
    method = String(method)

    if shape === :notification
        if method == "notifications/initialized"
            mark_initialized!(ctx, session)
        elseif method == "notifications/cancelled" && isnothing(req)
            # Only routeless (stdio) listen streams can be cancelled in-band;
            # on HTTP a notification can arrive on any connection (see
            # `cancel_listen!`). Per JSON-RPC, a cancelled request gets no
            # response.
            params = get(payload, "params", nothing)
            if !(params isa AbstractDict)
                return nothing, 202
            end
            request_id = get(params, "requestId", nothing)
            if !isnothing(request_id)
                cancel_listen!(ctx, request_id)
            end
        end
        return nothing, 202
    end

    id = payload["id"]
    params = request_params(payload)

    spec = request_spec(ctx, req, method, params; session=session)
    if isnothing(spec)
        return unsupported_version_response(id, params)
    end

    try
        validate_request(spec, ctx, req, method, params)
    catch error
        if !(error isa MCPRequestError)
            rethrow()
        end
        return request_error_body(id, error), 400
    end

    return dispatch(ctx, req, id, method, payload; spec=spec, session=session)
end

# The `-32022` response for a request claiming a modern revision this server
# does not serve. `request_spec` returns `nothing` only for such a claim, so the
# requested version is always the string in `_meta.protocolVersion`.
function unsupported_version_response(id, params)::Tuple{Dict{String,Any},Int}
    meta = get(params, META_KEY, nothing)
    requested = meta isa AbstractDict ? get(meta, META_PROTOCOL, nothing) : nothing
    return error_body(id, MCP_UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version",
                      Dict{String,Any}(
                          "supported" => copy(SUPPORTED_VERSIONS),
                          "requested" => requested,
                      )), 400
end

"""
    process_batch(ctx, payload, req; session) :: (body, status)

Handle a JSON-RPC batch. Batching existed only in the `2025-03-26` revision
(it was removed in `2025-06-18`), so a batch is accepted only when the
effective legacy version is exactly that revision. Notifications produce no
entries; a batch of only notifications answers `202` with no body. Streamed
tool calls are drained to their terminal JSON body (batches never upgrade to
SSE), and `subscriptions/listen` is rejected because it is a modern-only
stream.
"""
function process_batch(ctx::ServerContext, payload::AbstractVector,
                       req::Union{Nothing,HTTP.Request};
                       session::Union{Nothing,MCPSession}=nothing)
    if isempty(payload)
        return error_body(nothing, MCP_INVALID_REQUEST, "Invalid Request: empty batch"), 400
    end

    if !isnothing(request_claim(req, "", Dict{String,Any}()))
        return error_body(nothing, MCP_INVALID_REQUEST,
                          "Batch requests are not supported in the modern era"), 400
    end

    # Batching existed only in 2025-03-26, so the effective legacy spec decides.
    if !allows_batch(legacy_spec(ctx, session))
        return error_body(
            nothing, MCP_INVALID_REQUEST,
            "Batch requests require the $(version_string(V2025_03_26)) protocol revision"), 400
    end

    responses = Any[]
    for entry in payload
        body, _ = process(ctx, entry, req; session=session)
        if body isa StreamedCall
            body = streamed_body(ctx, body, drain_stream!(body.stream))
        elseif body isa ListenCall
            cancel_stream!(body.stream)
            body = error_body(body.id, MCP_INVALID_REQUEST,
                              "subscriptions/listen is not available in a batch")
        end
        if !isnothing(body)
            push!(responses, body)
        end
    end

    if isempty(responses)
        return nothing, 202
    end
    return responses, 200
end

end # module JSONRPC
