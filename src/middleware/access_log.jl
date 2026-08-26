module AccessLogMiddleware

using HTTP
using Dates

export AccessLog, common_logfmt, combined_logfmt, @logfmt_str

@doc raw"""
    logfmt"..."

Parse an [NGINX-style log format string](https://nginx.org/en/docs/http/ngx_http_log_module.html#log_format)
and return a function mapping `(io::IO, req::HTTP.Request) -> nothing` suitable for passing
to the [`AccessLog`](@ref) middleware as its `format` keyword argument.

The following variables are currently supported:

 - `$http_name`: arbitrary request header (with `-` replaced with `_`, e.g. `http_user_agent`)
 - `$sent_http_name`: arbitrary response header (with `-` replaced with `_`)
 - `$request`: the request line, e.g. `GET /index.html HTTP/1.1`
 - `$request_method`: the request method
 - `$request_uri`: the request URI
 - `$remote_addr`: client address
 - `$remote_port`: client port
 - `$remote_user`: user name supplied with the Basic authentication
 - `$server_protocol`: server protocol
 - `$time_iso8601`: local time in ISO8601 format
 - `$time_local`: local time in Common Log Format
 - `$status`: response status code
 - `$body_bytes_sent`: number of bytes in response body

## Examples
```julia
logfmt"[\$time_iso8601] \\"\$request\\" \$status" # [2021-05-01T12:34:40+0100] "GET /index.html HTTP/1.1" 200

logfmt"\$remote_addr \\"\$http_user_agent\\"" # 127.0.0.1 "curl/7.47.0"
```
"""
macro logfmt_str(s)
    return logfmt_parser(s)
end

function logfmt_parser(s)
    s = String(s)
    vars = Symbol[]
    ex = Expr(:call, :print, :io)
    i = 1
    while i <= lastindex(s)
        j = findnext(==('\$'), s, i)
        if j === nothing
            j = lastindex(s)
            push!(ex.args, String(s[i:j]))
            break
        end
        if j > i
            push!(ex.args, String(s[i:prevind(s, j)]))
        end
        sym, j = Meta.parse(s, nextind(s, j); greedy=false)
        e = symbol_mapping(sym)
        isa(e, Tuple) ? push!(ex.args, e...) : push!(ex.args, e)
        i = j
    end
    f = Expr(:->, Expr(:tuple, :io, :http), ex)
    return f
end

# Fetch the final response for the current request (attached by the AccessLog middleware)
get_response(http::HTTP.Request) :: HTTP.Response = get(() -> HTTP.Response(), http.context, :response)

# Resolve the client port from the stream attached by Oxygen's stream handler
function remote_port(http::HTTP.Request) :: String
    stream = get(http.context, :stream, nothing)
    stream === nothing && return "-"
    addr = HTTP.peeraddr(stream)
    addr === nothing && return "-"
    return string(addr.port)
end

# Number of bytes in the response body (replaces `http.nwritten` from HTTP.jl 1.x)
function body_bytes_sent(response::HTTP.Response) :: Int
    response.content_length >= 0 && return Int(response.content_length)
    body = response.body
    if body isa Union{Vector{UInt8}, Base.CodeUnits}
        return length(body)
    elseif body isa AbstractString
        return sizeof(body)
    else
        return 0
    end
end

function symbol_mapping(s::Symbol)
    str = string(s)
    if (m = match(r"^http_(.+)$", str); m !== nothing)
        hdr = replace(String(m[1]), '_' => '-')
        :(HTTP.header(http, $hdr, "-"))
    elseif (m = match(r"^sent_http_(.+)$", str); m !== nothing)
        hdr = replace(String(m[1]), '_' => '-')
        :(HTTP.header(get_response(http), $hdr, "-"))
    elseif s === :remote_addr
        :(string(get(() -> "-", http.context, :ip)))
    elseif s === :remote_port
        :(remote_port(http))
    elseif s === :remote_user
        :("-") # TODO: find from Basic auth...
    elseif s === :time_iso8601
        if !Sys.iswindows()
            :(Libc.strftime("%FT%T%z", time()))
        else
            # TODO: Libc.strftime doesn't seem to work properly on Windows
            # so format without timezone using Dates stdlib
            :(Dates.format(now(), dateformat"yyyy-mm-dd\THH:MM:SS"))
        end
    elseif s === :time_local
        if !Sys.iswindows()
            :(Libc.strftime("%d/%b/%Y:%H:%M:%S %z", time()))
        else
            # TODO: Libc.strftime doesn't seem to work properly on Windows
            # so format without timezone using Dates stdlib
            :(Dates.format(now(), dateformat"dd/u/yyyy:HH:MM:SS"))
        end
    elseif s === :request
        m = symbol_mapping(:request_method)
        t = symbol_mapping(:request_uri)
        p = symbol_mapping(:server_protocol)
        (m, " ", t, " ", p...)
    elseif s === :request_method
        :(http.method)
    elseif s === :request_uri
        :(http.target)
    elseif s === :server_protocol
        ("HTTP/", :(Int(http.version.major)), ".", :(Int(http.version.minor)))
    elseif s === :status
        :(get_response(http).status)
    elseif s === :body_bytes_sent
        return :(max(0, body_bytes_sent(get_response(http))))
    else
        error("unknown variable in logfmt: $s")
    end
end

"""
    common_logfmt(io::IO, http::HTTP.Request)

Format a log message in the Common Log Format and write to `io`.
"""
const common_logfmt = logfmt"$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent"

"""
    combined_logfmt(io::IO, http::HTTP.Request)

Format a log message in the Combined Log Format and write to `io`.
"""
const combined_logfmt = logfmt"$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent \"$http_referer\" \"$http_user_agent\""

"""
    AccessLog(; format=common_logfmt)

Middleware that writes a per-request access log entry after each request completes.
The `format` argument is any function `(io::IO, req::HTTP.Request) -> nothing`, such as one
created with the `logfmt"..."` string macro, [`common_logfmt`](@ref), or
[`combined_logfmt`](@ref).

Log entries are emitted through Julia's logging system at the `Info` level with the
keyword `_group=:access`, so they can be filtered or routed independently of other log
messages (e.g. with LoggingExtras.jl).

# Example

```julia
serve(middleware=[AccessLog()], docs=false, metrics=false)

serve(middleware=[AccessLog(format=logfmt"[\$time_iso8601] \\"\$request\\" \$status")])
```
"""
function AccessLog(;
    format  :: Function = common_logfmt
)
    return function(handle::Function)
        return function(req::HTTP.Request)
            response = handle(req)
            try
                # attach the response so formatters can reference $status,
                # $sent_http_* and $body_bytes_sent values
                req.context[:response] = response
                @info sprint(format, req) _group=:access
            catch error
                @warn "AccessLog: failed to write access log entry" exception=(error, catch_backtrace())
            end
            return response
        end
    end
end

end