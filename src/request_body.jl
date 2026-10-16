module RequestBody

using HTTP
using JSON

export request_bytes, text, binary, json, formdata

# Request-body readers shared by `CoreUtils` (the lazy `LazyRequest` accessors)
# and `Util` (the public convenience functions). Deliberately dependency-free:
# it loads before `Types`, `Reflection`, and `Util`, so none of them have to
# depend on a higher layer for basic body parsing.

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

end
