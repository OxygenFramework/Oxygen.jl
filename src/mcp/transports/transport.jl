# Streamable HTTP transport endpoints and pre-dispatch rejection.
# Included into `MCP.Transports` by `../transports.jl`.

# ----------------------------------------------------------------------------
# Origin guard
# ----------------------------------------------------------------------------

function check_origin(ctx::ServerContext, req::HTTP.Request)
    origin = HTTP.header(req, "Origin", nothing)
    if isnothing(origin) || isempty(origin)
        return nothing
    end

    origin = String(origin)

    # Explicit allowlist always wins
    if origin in ctx.mcp.allowed_origins
        return nothing
    end

    # Same-host origins are permitted by default
    host = HTTP.header(req, "Host", nothing)
    if !isnothing(host)
        origin_host = try
            uri = HTTP.URI(origin)
            port = isnothing(uri.port) ? "" : ":" * string(uri.port)
            string(something(uri.host, "")) * port
        catch
            ""
        end
        if !isempty(origin_host) && origin_host == String(host)
            return nothing
        end
    end

    return HTTP.Response(403, "Forbidden")
end

# Pre-dispatch transport rejections: origin allowlist, JSON content type, and
# (informationally) an unknown protocol version header. Writes the fixed
# rejection itself and returns `true` when the request was answered.
function reject_transport(ctx::ServerContext, stream::HTTP.Stream, req::HTTP.Request)::Bool
    origin_response = check_origin(ctx, req)
    if !isnothing(origin_response)
        write_stream_response(stream, origin_response.status, "text/plain; charset=utf-8", "Forbidden")
        return true
    end

    # Explicit Content-Type: only JSON bodies are accepted. Accept-header
    # handling is deliberately lenient; clients that send no or partial Accept
    # headers still work.
    content_type = HTTP.header(req, "Content-Type", "")
    if !startswith(String(content_type), "application/json")
        write_stream_response(stream, 415, "text/plain", "Unsupported Media Type")
        return true
    end

    # Version header handling is lenient for legacy traffic (no mirroring
    # required), but an unknown version is worth surfacing. Modern requests are
    # strictly validated later, so this is informational only.
    header_version = HTTP.header(req, "MCP-Protocol-Version", "")
    if !isempty(header_version) && !(strip(String(header_version)) in SUPPORTED_VERSIONS)
        @debug "Client requested unsupported protocol version" client_version=String(header_version) supported=SUPPORTED_VERSIONS
    end
    return false
end

# Write a dispatch result. Streamed tool calls and listen streams upgrade to
# SSE; a `nothing` body (notification or client response) writes a bare status;
# everything else is a JSON reply.
function write_result(ctx::ServerContext, stream::HTTP.Stream, req::HTTP.Request,
                      body, status::Int, headers::Vector{Pair{String,String}})
    if body isa StreamedCall
        return stream_call(ctx, stream, req, body)
    elseif body isa ListenCall
        return stream_listen_call(ctx, stream, req, body)
    elseif isnothing(body)
        return write_stream_response(stream, status, "text/plain; charset=utf-8", "")
    end
    return write_json_response(stream, body; status=status, headers=headers)
end

"""
    handle(ctx::ServerContext, stream::HTTP.Stream)

Streamable HTTP transport entry point. The `POST` route is registered as a
streaming route, so both the JSON and the SSE replies are written directly to
the raw stream:

- requests that are not `tools/call`, or whose tool never emits a
  notification, are answered with the exact JSON bytes the buffered route used
  to produce;
- a streamed call whose first event is a notification upgrades to SSE
  (`text/event-stream`, `Cache-Control: no-cache`, `X-Accel-Buffering: no`),
  flushes every frame, and keeps the stream alive with `: keepalive` comments
  while the producer is idle.

Origin checks, modern header validation, and body parsing all run before any
streaming starts. Legacy HTTP clients get a session id from `initialize` (see
`mcp/sessions.jl`); clients that echo it are isolated, while header-less
requests keep using the context-wide anonymous state.
"""
function handle(ctx::ServerContext, stream::HTTP.Stream)
    req = buffered_request(stream)

    reject_transport(ctx, stream, req) && return nothing

    decoded, payload = decode_body(req)
    decoded || return write_json_response(stream, error_body(nothing, MCP_PARSE_ERROR, "Parse error"); status=400)

    # The revision's transport policy decides whether this request is stateful:
    # a modern claim never resolves a session, a legacy request uses its
    # session (or the anonymous context-wide state).
    stateful = uses_sessions(transport_spec(ctx, req, payload))

    # Sessions only exist in the legacy era. A supplied id must name a live
    # session (404 otherwise, per the Streamable HTTP transport).
    session = stateful ? resolve_session_or_error(ctx, req) : nothing
    if session isa Tuple
        status, body = session
        return write_json_response(stream, body; status=status)
    end

    if payload isa AbstractVector
        body, status = process_batch(ctx, payload, req; session=session)
        return write_result(ctx, stream, req, body, status, Pair{String,String}[])
    end

    method = payload isa AbstractDict ? get(payload, "method", "") : ""

    # A header-less initialize mints a session before dispatch and mirrors its
    # state afterwards; the response is the only place the client learns its id.
    initialize = stateful && method == "initialize"
    minted = initialize && !(session isa MCPSession)
    if minted
        session = new_session!(ctx)
    end

    body, status = process(ctx, payload, req; session=session)

    response_headers = Pair{String,String}[]
    if initialize
        if minted
            mirror_anonymous!(ctx, session)
        end
        push!(response_headers, SESSION_HEADER => session.id)
    end
    return write_result(ctx, stream, req, body, status, response_headers)
end

"""
    handle_get(ctx::ServerContext, stream::HTTP.Stream)

HTTP `GET` on the MCP endpoint, registered through the streaming route so it can
either answer with a fixed body or hold the connection open for SSE.

- A GET whose policy revision rejects the endpoint (`get_policy`; the modern era
  removed it) gets `405`.
- A GET with `Accept: text/event-stream` opens the legacy server→client
  notification stream and keeps it open until the client disconnects.
- Any other GET returns a JSON health body, which lets clients health-check the
  endpoint.
"""
function handle_get(ctx::ServerContext, stream::HTTP.Stream)
    req = stream.message

    # The legacy notification stream is a privileged sink too: without this
    # check a DNS-rebinding page could read server-initiated notifications. The
    # guard runs before every GET reply, matching `handle`.
    origin_response = check_origin(ctx, req)
    if !isnothing(origin_response)
        return write_stream_response(stream, origin_response.status, "text/plain; charset=utf-8", "Forbidden")
    end

    # A body-less GET carries no `_meta`, so its policy revision comes from the
    # version header alone.
    if get_policy(transport_spec(ctx, req)) === :reject
        return write_stream_response(stream, 405, "text/plain", "Method Not Allowed";
                                     headers=["Allow" => "POST"])
    end

    resolved = resolve_session_or_error(ctx, req)
    if resolved isa Tuple
        status, body = resolved
        return write_json_response(stream, body; status=status)
    end
    session = resolved isa MCPSession ? resolved : nothing

    if accepts_event_stream(req; explicit=true)
        return stream_notifications(ctx, stream; session=session)
    end

    body = Dict{String,Any}(
        "status" => "ok",
        "protocol_version" => legacy_version(ctx, session),
    )
    return write_json_response(stream, body)
end

"""
    handle_delete(ctx, req) :: HTTP.Response

Terminate the legacy session named by `Mcp-Session-Id`. A DELETE without the
header is `405` (the server does not accept anonymous termination), an unknown
or expired id is `404`, and the modern era, which has no sessions, is `405`.
An accepted termination closes the session's notification streams and removes
its state; later requests naming it get `404`.
"""
function handle_delete(ctx::ServerContext, req::HTTP.Request)::HTTP.Response
    # A DELETE carries no body: its policy revision comes from the version
    # header alone. Revisions that reject DELETE answer before session
    # resolution, so a bad session id cannot mask the 405.
    if delete_policy(transport_spec(ctx, req)) === :reject
        return HTTP.Response(405, ["Allow" => "POST, GET"], "Method Not Allowed")
    end

    resolved = resolve_session_or_error(ctx, req)
    if resolved isa Tuple
        status, body = resolved
        return HTTP.Response(status, ["Content-Type" => "application/json; charset=utf-8"],
                             JSON.json(body))
    elseif isnothing(resolved)
        return HTTP.Response(405, ["Allow" => "POST, GET"], "Method Not Allowed")
    end

    session = resolved::MCPSession
    terminate_session!(ctx, session)
    lock(ctx.mcp.sessions_lock) do
        delete!(ctx.mcp.sessions, session.id)
    end
    return HTTP.Response(200, ["Content-Type" => "application/json; charset=utf-8"],
                         JSON.json(Dict{String,Any}("status" => "terminated")))
end
