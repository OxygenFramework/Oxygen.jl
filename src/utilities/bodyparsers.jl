using HTTP
using JSON
using URIs

export text, binary, json, formdata

### Helper functions used to parse the body of a HTTP.Request object

request_bytes(req::HTTP.Request) = req.body isa HTTP.EmptyBody ? UInt8[] : copy(req.body)

"""
    text(request::HTTP.Request)

Read the body of a HTTP.Request as a String
"""
function text(req::HTTP.Request) :: String
    body = IOBuffer(request_bytes(req))
    return eof(body) ? nothing : read(seekstart(body), String)
end


"""
    formdata(request::HTTP.Request)

Read the html form data from the body of a HTTP.Request
"""
function formdata(req::HTTP.Request) :: Dict
    return HTTP.queryparams(text(req))
end


"""
    binary(request::HTTP.Request)

Read the body of a HTTP.Request as a Vector{UInt8}
"""
function binary(req::HTTP.Request) :: Vector{UInt8}
    body = IOBuffer(request_bytes(req))
    return eof(body) ? nothing : readavailable(body)
end


"""
    json(request::HTTP.Request; keyword_arguments...)

Read the body of a HTTP.Request as JSON with additional arguments for the read/serializer.
"""
function json(req::HTTP.Request; kwargs...)
    body = IOBuffer(request_bytes(req))
    return eof(body) ? nothing : JSON.parse(body; kwargs...)
end

"""
    json(request::HTTP.Request, class_type; keyword_arguments...)

Read the body of a HTTP.Request as JSON with additional arguments for the read/serializer into a custom struct.
"""
function json(req::HTTP.Request, class_type::Type{T}; kwargs...) :: T where {T}
    body = IOBuffer(request_bytes(req))
    return eof(body) ? nothing : JSON.parse(body, class_type; kwargs...)
end


### Helper functions used to parse the body of an HTTP.Response object

function response_bytes(response::HTTP.Response) :: Vector{UInt8}
    body = response.body
    body isa HTTP.EmptyBody && return UInt8[]
    body isa HTTP.BytesBody && return copy(body)
    # raw String/Vector{UInt8} bodies assigned directly to a response
    body isa HTTP.AbstractBody || return Vector{UInt8}(body)
    # streaming bodies (e.g. file responses from HTTP.servefile) can only be drained incrementally
    out = IOBuffer()
    buffer = Vector{UInt8}(undef, 8192)
    while true
        n = HTTP.body_read!(body, buffer)
        n == 0 && break
        write(out, view(buffer, 1:n))
    end
    return take!(out)
end

"""
    text(response::HTTP.Response)

Read the body of a HTTP.Response as a String
"""
function text(response::HTTP.Response) :: String
    return String(response_bytes(response))
end

"""
    formdata(request::HTTP.Response)

Read the html form data from the body of a HTTP.Response
"""
function formdata(response::HTTP.Response) :: Dict
    return HTTP.queryparams(text(response))
end


"""
    json(response::HTTP.Response; keyword_arguments)

Read the body of a HTTP.Response as JSON with additional keyword arguments
"""
function json(response::HTTP.Response; kwargs...) :: JSON.Object
    return JSON.parse(response_bytes(response); kwargs...)
end


"""
    json(response::HTTP.Response, class_type; keyword_arguments)

Read the body of a HTTP.Response as JSON with additional keyword arguments and serialize it into a custom struct
"""
function json(response::HTTP.Response, class_type::Type{T}; kwargs...) :: T where {T}
    return JSON.parse(response_bytes(response), class_type; kwargs...)
end


