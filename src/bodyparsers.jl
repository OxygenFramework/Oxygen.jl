module BodyParsers 

using HTTP 
using JSON3

export text, binary, json

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
    return eof(body) ? nothing : JSON3.read(body; kwargs...)    
end

"""
    json(request::HTTP.Request, classtype; keyword_arguments...)

Read the body of a HTTP.Request as JSON with additional arguments for the read/serializer into a custom struct.
"""
function json(req::HTTP.Request, classtype; kwargs...)
    body = IOBuffer(HTTP.payload(req))
    return eof(body) ? nothing : JSON3.read(body, classtype; kwargs...)    
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
    json(response::HTTP.Response; keyword_arguments)

Read the body of a HTTP.Response as JSON with additional keyword arguments
"""
function json(response::HTTP.Response; kwargs...) :: JSON3.Object
    return JSON3.read(String(response.body); kwargs...)
end


"""
    json(response::HTTP.Response, classtype; keyword_arguments)

Read the body of a HTTP.Response as JSON with additional keyword arguments and serialize it into a custom struct
"""
function json(response::HTTP.Response, classtype; kwargs...)
    return JSON3.read(String(response.body), classtype; kwargs...)
end

end