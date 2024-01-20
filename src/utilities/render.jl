
using HTTP
using JSON3

export Renderer, html, text, json, xml, js, css, binary

struct Renderer 
    response::HTTP.Response
end

"""
    html(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as HTML
"""
function html(content::String; status = 200, headers = ["Content-Type" => "text/html; charset=utf-8"]) :: Renderer
    push!(headers, "Content-Length" => string(length(content)))
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    text(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as plain text
"""
function text(content::String; status = 200, headers = ["Content-Type" => "text/plain; charset=utf-8"]) :: Renderer
    push!(headers, "Content-Length" => string(length(content)))
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    json(content::Any; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as JSON
"""
function json(content::Any; status = 200, headers = ["Content-Type" => "application/json; charset=utf-8"]) :: Renderer
    body = JSON3.write(content)
    push!(headers, "Content-Length" => string(length(body)))
    return HTTP.Response(status, headers, body = body) |> Renderer
end

"""
    xml(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as XML
"""
function xml(content::String; status = 200, headers = ["Content-Type" => "application/xml; charset=utf-8"]) :: Renderer
    push!(headers, "Content-Length" => string(length(content)))
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    js(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as JavaScript
"""
function js(content::String; status = 200, headers = ["Content-Type" => "application/javascript; charset=utf-8"]) :: Renderer
    push!(headers, "Content-Length" => string(length(content)))
    return HTTP.Response(status, headers, body = content) |> Renderer
end



"""
    css(content::String; status::Int, headers::Pair)

A convenience function to return a String that should be interpreted as CSS
"""
function css(content::String; status = 200, headers = ["Content-Type" => "text/css; charset=utf-8"]) :: Renderer
    push!(headers, "Content-Length" => string(length(content)))
    return HTTP.Response(status, headers, body = content) |> Renderer
end

"""
    binary(content::Vector{UInt8}; status::Int, headers::Pair)

A convenience function to return a Vector of UInt8 that should be interpreted as binary data
"""
function binary(content::Vector{UInt8}; status = 200, headers = ["Content-Type" => "application/octet-stream"]) :: Renderer
    push!(headers, "Content-Length" => string(length(content)))
    return HTTP.Response(status, headers, body = content) |> Renderer
end