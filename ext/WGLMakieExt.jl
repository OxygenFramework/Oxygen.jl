module WGLMakieExt

import HTTP
import Oxygen: html, BONITO_OFFLINE # import the html function from util so we can override it
import Bonito: Page
import WGLMakie.Makie: FigureLike

export html

const HTML  = MIME"text/html"()

"""
Converts a Figure object to the designated MIME type and wraps it inside an HTTP response.
"""
function response(content::FigureLike, mime_type::MIME, status::Int, headers::Vector, offline=BONITO_OFFLINE[])
    # Force inlining all data & js dependencies
    Page(exportable=true, offline=offline)

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
    html(fig::Makie.FigureLike) :: HTTP.Response

Convert a Makie figure to HTML and wrap it inside an HTTP response.
"""
html(fig::FigureLike, status=200, headers=[], offline=BONITO_OFFLINE[]) :: HTTP.Response = response(fig, HTML, status, headers, offline)

end
