
using HTTP
using JSON3
using MIMEs

export Renderer, html, text, json, xml, js, css, binary, file

struct Renderer 
    response::HTTP.Response
end

"""
    html(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as HTML
"""
function html(content::String; status = 200, headers = []) :: Renderer
    push!(headers, 
        "Content-Type" => "text/html; charset=utf-8",
        "Content-Length" => string(sizeof(content))
    )
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    text(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as plain text
"""
function text(content::String; status = 200, headers = []) :: Renderer
    push!(headers, 
        "Content-Type" => "text/plain; charset=utf-8",
        "Content-Length" => string(sizeof(content))
    )
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    json(content::Any; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as JSON
"""
function json(content::Any; status = 200, headers = []) :: Renderer
    body = JSON3.write(content)
    push!(headers, 
        "Content-Type" => "application/json; charset=utf-8",
        "Content-Length" => string(sizeof(body))
    )
    return HTTP.Response(status, headers, body = body) |> Renderer
end

"""
    xml(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as XML
"""
function xml(content::String; status = 200, headers = []) :: Renderer
    push!(headers, 
        "Content-Type" => "application/xml; charset=utf-8",
        "Content-Length" => string(sizeof(content))
    )
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    js(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as JavaScript
"""
function js(content::String; status = 200, headers = []) :: Renderer
    push!(headers, 
        "Content-Type" => "application/javascript; charset=utf-8",
        "Content-Length" => string(sizeof(content))
    )
    return HTTP.Response(status, headers, body = content) |> Renderer
end


"""
    css(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as CSS
"""
function css(content::String; status = 200, headers = []) :: Renderer
    push!(headers, 
        "Content-Type" => "text/css; charset=utf-8",
        "Content-Length" => string(sizeof(content)), 
    )
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    binary(content::Vector{UInt8}; status::Int, headers::Pair)

A convenience function to return a Vector of UInt8 that should be interpreted as binary data
"""
function binary(content::Vector{UInt8}; status = 200, headers = []) :: Renderer
    push!(headers, 
        "Content-Type" => "application/octet-stream",
        "Content-Length" => string(sizeof(content))
    )
    return HTTP.Response(status, headers, body = content) |> Renderer
end


"""
    file(filepath::String; loadfile=nothing, status = 200, headers = []) :: Renderer

Reads a file and returns a Renderer object. The file is read as binary. If the file does not exist, 
an ArgumentError is thrown. The MIME type and the size of the file are added to the headers.

# Arguments
- `filepath`: The path to the file to be read.
- `loadfile`: An optional function to load the file. If not provided, the file is read using the `open` function.
- `status`: The HTTP status code to be used in the response. Defaults to 200.
- `headers`: Any additional headers to be included in the response. Defaults to an empty array.

# Returns
- A Renderer object containing the HTTP response.
"""
function file(filepath::String; loadfile = nothing, status = 200, headers = []) :: Renderer
    has_loadfile    = !isnothing(loadfile)
    content         = has_loadfile ? loadfile(filepath) : read(open(filepath), String)
    content_length  = has_loadfile ? string(sizeof(content)) : string(filesize(filepath))
    content_type    = mime_from_path(filepath, MIME"application/octet-stream"()) |> contenttype_from_mime
    push!(headers, "Content-Type" => content_type, "Content-Length" => content_length)
    return HTTP.Response(status, headers, body = content) |> Renderer
end
