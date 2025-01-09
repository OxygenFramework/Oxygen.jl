module BonitoExt

import HTTP
import Oxygen.Util: html # import the html function from util so we can override it
import Bonito: Page, App

export html

const HTML  = MIME"text/html"()

"""
Converts a Figure object to the designated MIME type and wraps it inside an HTTP response.
"""
function response(content::App, mime_type::MIME, status::Int, headers::Vector)
    # Force inlining all data & js dependencies
    Page(exportable=true, offline=true)

    # Convert & load the figure into an IOBuffer
    io = IOBuffer()
    show(io, mime_type, content)
    body = take!(io)
    
    # format the response
    resp = HTTP.Response(status, headers, body)
    HTTP.setheader(resp, "Content-Type" => string(mime_type))
    HTTP.setheader(resp, "Content-Length" => string(sizeof(body)))
    return resp
end

"""
    html(app::Bonito.App) :: HTTP.Response

Convert a Bonito.App to HTML and wrap it inside an HTTP response.
"""
html(app::App, status=200, headers=[]) :: HTTP.Response = response(app, HTML, status, headers)

end