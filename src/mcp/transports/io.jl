# Low-level HTTP request decoding and response writing.
# Included into `MCP.Transports` by `../transports.jl`.

"""
    write_stream_response(stream, status, content_type, body; headers=[])

Write a complete, non-streaming HTTP response directly to a raw `HTTP.Stream`.
The MCP `GET` route is registered as a streaming route (so it can hold the
connection open for SSE), so its fixed-body replies are written by hand.
"""
function write_stream_response(
    stream::HTTP.Stream,
    status::Int,
    content_type::String,
    body::AbstractString;
    headers::Vector{Pair{String,String}}=Pair{String,String}[])

    HTTP.setstatus(stream, status)
    HTTP.setheader(stream, "Content-Type" => content_type)
    # These fixed-body replies are written by a streaming handler, so the server
    # cannot manage connection reuse for them; close explicitly to keep clients
    # from pooling a socket that will not be reused.
    HTTP.setheader(stream, "Connection" => "close")
    for (name, value) in headers
        HTTP.setheader(stream, name => value)
    end
    HTTP.setheader(stream, "Content-Length" => string(ncodeunits(body)))
    HTTP.startwrite(stream)
    write(stream, body)
    HTTP.closewrite(stream)
    return nothing
end

function write_json_response(
    stream::HTTP.Stream,
    body;
    status::Int=200,
    headers::Vector{Pair{String,String}}=Pair{String,String}[])

    return write_stream_response(stream, status, "application/json; charset=utf-8", JSON.json(body);
                                 headers=headers)
end

function write_sse_frame(stream::HTTP.Stream, payload)
    write(stream, "event: message\n")
    write(stream, "data: ", JSON.json(payload), "\n\n")
    flush(stream)
    return nothing
end

# The transport adapter decodes the request body before middleware runs, so the
# stream's own message carries headers only; `decorate_request` stashes the
# buffered request (body included) on the shared request context.
function buffered_request(stream::HTTP.Stream) :: HTTP.Request
    request = get(stream.message.context, :buffered_request, stream.message)
    return request isa HTTP.Request ? request : stream.message
end

# Decode the JSON request body; `(false, nothing)` marks a malformed body.
function decode_body(req::HTTP.Request) :: Tuple{Bool,Any}
    try
        return true, JSON.parse(String(req.body))
    catch
        # A malformed body is reported as a parse error by the caller.
        return false, nothing
    end
end
