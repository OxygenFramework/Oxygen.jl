
using HTTP
using JSON3
using MIMEs

export html, text, json, xml, js, css, binary, file

"""
    html(content::String; status::Int, headers::Vector{Pair}) :: HTTP.Response

A convenience function to return a String that should be interpreted as HTML
"""
function html(content::String; status = 200, headers = []) :: HTTP.Response
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => "text/html; charset=utf-8")
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end


"""
    text(content::String; status::Int, headers::Vector{Pair}) :: HTTP.Response

A convenience function to return a String that should be interpreted as plain text
"""
function text(content::String; status = 200, headers = []) :: HTTP.Response
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => "text/plain; charset=utf-8")
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end

"""
    json(content::Any; status::Int, headers::Vector{Pair}) :: HTTP.Response

A convenience function to return a String that should be interpreted as JSON
"""
function json(content::Any; status = 200, headers = []) :: HTTP.Response
    body = JSON3.write(content)
    response = HTTP.Response(status, headers, body = body)
    HTTP.setheader(response, "Content-Type" => "application/json; charset=utf-8")
    HTTP.setheader(response, "Content-Length" => string(sizeof(body)))
    return response
end

"""
    json(content::Vector{UInt8}; status::Int, headers::Vector{Pair}) :: HTTP.Response

A helper function that can be passed binary data that should be interpreted as JSON. 
No conversion is done on the content since it's already in binary format.
"""
function json(content::Vector{UInt8}; status = 200, headers = []) :: HTTP.Response
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => "application/json; charset=utf-8")
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end


"""
    xml(content::String; status::Int, headers::Vector{Pair}) :: HTTP.Response

A convenience function to return a String that should be interpreted as XML
"""
function xml(content::String; status = 200, headers = []) :: HTTP.Response
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => "application/xml; charset=utf-8")
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end

"""
    js(content::String; status::Int, headers::Vector{Pair}) :: HTTP.Response

A convenience function to return a String that should be interpreted as JavaScript
"""
function js(content::String; status = 200, headers = []) :: HTTP.Response
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => "application/javascript; charset=utf-8")
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end


"""
    css(content::String; status::Int, headers::Vector{Pair}) :: HTTP.Response

A convenience function to return a String that should be interpreted as CSS
"""
function css(content::String; status = 200, headers = []) :: HTTP.Response
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => "text/css; charset=utf-8")
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end

"""
    binary(content::Vector{UInt8}; status::Int, headers::Vector{Pair}) :: HTTP.Response

A convenience function to return a Vector of UInt8 that should be interpreted as binary data
"""
function binary(content::Vector{UInt8}; status = 200, headers = []) :: HTTP.Response
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => "application/octet-stream")
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end


"""
    file(filepath::String; loadfile=nothing, status = 200, headers = []) :: HTTP.Response

Reads a file and returns a HTTP.Response. The file is read as binary. If the file does not exist, 
an ArgumentError is thrown. The MIME type and the size of the file are added to the headers.

# Arguments
- `filepath`: The path to the file to be read.
- `loadfile`: An optional function to load the file. If not provided, the file is read using the `open` function.
- `status`: The HTTP status code to be used in the response. Defaults to 200.
- `headers`: Any additional headers to be included in the response. Defaults to an empty array.

# Returns
- A HTTP response.
"""
function file(filepath::String; loadfile = nothing, status = 200, headers = []) :: HTTP.Response
    has_loadfile    = !isnothing(loadfile)
    content         = has_loadfile ? loadfile(filepath) : read(filepath, String)
    content_length  = has_loadfile ? string(sizeof(content)) : string(filesize(filepath))
    content_type    = mime_from_path(filepath, MIME"application/octet-stream"()) |> contenttype_from_mime
    response = HTTP.Response(status, headers, body = content)
    HTTP.setheader(response, "Content-Type" => content_type)
    HTTP.setheader(response, "Content-Length" => content_length)
    return response
end
