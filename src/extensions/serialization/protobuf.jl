import HTTP
import .ProtoBuf: encode, decode, ProtoDecoder, ProtoEncoder

export protobuf

"""
    protobuf(request::HTTP.Request, type::Type{T}) :: T where {T}

Decode a protobuf message from the body of an HTTP request.

# Arguments
- `request`: An HTTP request object containing the protobuf message in its body.
- `type`: The type of the protobuf message to decode.

# Returns
- The decoded protobuf message of the specified type.
"""
function protobuf(request::HTTP.Request, type::Type{T}) :: T where {T}
    io = IOBuffer(request.body)
    return decode(ProtoDecoder(io), type)
end


"""
    protobuf(content::T, url::String, method::String = "POST") :: HTTP.Request where {T}

Create a HTTP.Request and encode a protobuf message into the body

# Arguments
- `content`: The protobuf message to encode.
- `url`: The URL to which the request will be sent.
- `method`: The HTTP method for the request (default is "POST").
- `headers`: The HTTP headers for the request (default is an empty list).

# Returns
- An HTTP request object with the encoded protobuf message in its body.
"""
function protobuf(content::T, url::String; method = "POST", headers = []) :: HTTP.Request where {T}
    io = IOBuffer()
    encode(ProtoEncoder(io), content)
    body = take!(io)
    # Format the request
    request = HTTP.Request(method, url, headers, body)
    HTTP.setheader(request, "Content-Type" => "application/octet-stream")
    HTTP.setheader(request, "Content-Length" => string(sizeof(body)))
    return request
end


"""
    protobuf(content::T; status = 200, headers = []) :: HTTP.Response where {T}

Encode a protobuf message into the body of an HTTP response.

# Arguments
- `content`: The protobuf message to encode.
- `status`: The HTTP status code for the response (default is 200).
- `headers`: The HTTP headers for the response (default is an empty list).

# Returns
- An HTTP response object with the encoded protobuf message in its body.
"""
function protobuf(content::T; status = 200, headers = []) :: HTTP.Response where {T}
    io = IOBuffer()
    encode(ProtoEncoder(io), content)
    body = take!(io)
    # Format the response
    response = HTTP.Response(status, headers, body = body)
    HTTP.setheader(response, "Content-Type" => "application/octet-stream")
    HTTP.setheader(response, "Content-Length" => string(sizeof(body)))
    return response
end

