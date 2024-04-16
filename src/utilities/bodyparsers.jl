
using HTTP 
using JSON3
using StructTypes

export text, binary, json, partialjson, formdata

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
    return HTTP.URIs.queryparams(text(req))
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
function json(req::HTTP.Request, classtype::Type{T}; kwargs...) :: T where {T}
    body = IOBuffer(HTTP.payload(req))
    return eof(body) ? nothing : JSON3.read(body, classtype; kwargs...)    
end

"""
    partialjson(request::HTTP.Request, key::Symbol; keyword_arguments...) :: JSON3.Object

Read a specific key from the body of a HTTP.Request as JSON with additional arguments for the read/serializer.
"""
function partialjson(request::HTTP.Request, key::Symbol; kwargs...) :: JSON3.Object
    return JSON3.read(request.body; kwargs...)[key]
end

"""
    partialjson(request::HTTP.Request, key::Symbol, classtype::Type{T}; keyword_arguments...) :: T where {T}

Read a specific key from the body of a HTTP.Request as JSON and deserialize it into a custom struct with additional arguments for the read/serializer.
"""
function partialjson(request::HTTP.Request, key::Symbol, classtype::Type{T}; kwargs...) :: T where {T}
    partial = JSON3.read(request.body; kwargs...)[key]
    partial_with_symbols = Dict(Symbol(k) => v for (k, v) in partial)
    return StructTypes.constructfrom(T, partial_with_symbols)
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
    return HTTP.URIs.queryparams(text(response))
end


"""
    json(response::HTTP.Response; keyword_arguments)

Read the body of a HTTP.Response as JSON with additional keyword arguments
"""
function json(response::HTTP.Response; kwargs...) :: JSON3.Object
    return JSON3.read(response.body; kwargs...)
end


"""
    json(response::HTTP.Response, classtype; keyword_arguments)

Read the body of a HTTP.Response as JSON with additional keyword arguments and serialize it into a custom struct
"""
function json(response::HTTP.Response, classtype::Type{T}; kwargs...) :: T where {T}
    return JSON3.read(response.body, classtype; kwargs...)
end


