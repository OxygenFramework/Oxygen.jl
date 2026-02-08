
using HTTP 
using JSON
using ..Util

export text, binary, json, formdata

### Helper functions used to parse the body of a HTTP.Request object

"""
    text(request::HTTP.Request)

Read the body of a HTTP.Request as a String
"""
function text(req::HTTP.Request) :: String
    body = IOBuffer(HTTP.payload(req))
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
    body = IOBuffer(HTTP.payload(req))
    return eof(body) ? nothing : readavailable(body)
end


"""
    json(request::HTTP.Request; keyword_arguments...)

Read the body of a HTTP.Request as JSON with additional arguments for the read/serializer.
"""
function json(req::HTTP.Request; kwargs...)
    body = IOBuffer(HTTP.payload(req))
    return eof(body) ? nothing : JSON.parse(body; kwargs...)    
end

"""
    json(request::HTTP.Request, class_type; keyword_arguments...)

Read the body of a HTTP.Request as JSON with additional arguments for the read/serializer into a custom struct.
"""
function json(req::HTTP.Request, class_type::Type{T}; kwargs...) :: T where {T}
    body = IOBuffer(HTTP.payload(req))
    return eof(body) ? nothing : JSON.parse(body, class_type; kwargs...)    
end


### Helper functions used to parse the body of an HTTP.Response object


"""
    text(response::HTTP.Response)

Read the body of a HTTP.Response as a String
"""
function text(response::HTTP.Response) :: String
    return String(response.body)
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
    return JSON.parse(response.body; kwargs...)
end


"""
    json(response::HTTP.Response, class_type; keyword_arguments)

Read the body of a HTTP.Response as JSON with additional keyword arguments and serialize it into a custom struct
"""
function json(response::HTTP.Response, class_type::Type{T}; kwargs...) :: T where {T}
    return JSON.parse(response.body, class_type; kwargs...)
end


