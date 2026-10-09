using HTTP
using JSON
using URIs

# The request-body readers live in the lower-level `RequestBody` module so
# `Types` can use them without depending on `Util`; importing the bindings here
# keeps them as methods of the same functions Util exports.
import ..RequestBody: text, binary, json, formdata

export text, binary, json, formdata

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


