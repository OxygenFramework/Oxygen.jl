# HTTP `Accept` header parsing and event-stream negotiation.
# Included into `MCP.Transports` by `../transports.jl`.

# Collect every `Accept` header value (`Accept` may be spread across repeated
# header entries).
function accept_headers(req::HTTP.Request)::Vector{String}
    accept = String[]
    for (key, value) in req.headers
        if header_name_equals(key, "accept")
            push!(accept, String(value))
        end
    end
    return accept
end

# Split one `Accept` media-range into its lowercased media type and its `q`
# weight (default 1.0; a malformed weight is read as a refusal).
function parse_media_range(entry::AbstractString)::Tuple{String,Float64}
    fields = split(entry, ';')
    media = lowercase(strip(fields[1]))
    q = 1.0
    for field in fields[2:end]
        part = split(field, '='; limit=2)
        if length(part) == 2 && lowercase(strip(part[1])) == "q"
            q = something(tryparse(Float64, strip(part[2])), 0.0)
        end
    end
    return media, q
end

"""
    accepts_event_stream(req; explicit=false) :: Bool

Whether the request's `Accept` header allows a `text/event-stream` reply.
An explicit `text/event-stream` range decides on its own (`q=0` refuses);
otherwise `text/*` or `*/*` with a positive `q` accepts. A request with no
`Accept` header is treated as JSON-only, which keeps legacy clients on exactly
today's bytes.

With `explicit=true`, only an explicit `text/event-stream` range opts in; a
wildcard does not. The legacy `GET` endpoint uses this form so an `Accept: */*`
health check does not accidentally hold the connection open as SSE.
"""
function accepts_event_stream(req::HTTP.Request; explicit::Bool=false)::Bool
    accept = accept_headers(req)
    isempty(accept) && return false

    # Joining first flattens the per-header split into one loop; entries are
    # the same comma-separated media ranges, in order.
    wildcard = false
    for entry in split(join(accept, ','), ',')
        media, q = parse_media_range(entry)
        if isempty(media)
            continue
        end

        # An exact `text/event-stream` range decides on its own; a wildcard
        # only opts in, it never overrides an exact refusal.
        if media == "text/event-stream"
            return q > 0
        elseif !explicit && (media == "text/*" || media == "*/*") && q > 0
            wildcard = true
        end
    end
    return wildcard
end
