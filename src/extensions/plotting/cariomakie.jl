import HTTP
import .CairoMakie: Figure, text
import .Core.Util: html, text # import the html function from util so we can override it

export png, svg, pdf, html

# Here we list all our supported MIME types
const PNG   = MIME"image/png"()
const SVG   = MIME"image/svg+xml"()
const PDF   = MIME"application/pdf"()
const HTML  = MIME"text/html"()

"""
Converts a Figure object to the designated MIME type and wraps it inside an HTTP response.
"""
function response(fig::Figure, mime_type::MIME) :: HTTP.Response
    io = IOBuffer()
    show(io, mime_type, fig)
    body = take!(io)
    headers = [
        "Content-Type" => string(mime_type),
        "Content-Length" => string(sizeof(body))
    ]
    return HTTP.Response(200, headers, body)
end

"""
    svg(fig::Figure) :: HTTP.Response

Convert a figure to an PNG and wrap it inside an HTTP response.
"""
png(fig::Figure) :: HTTP.Response = response(fig, PNG)


"""
    svg(fig::Figure) :: HTTP.Response

Convert a figure to an SVG and wrap it inside an HTTP response.
"""
svg(fig::Figure) :: HTTP.Response = response(fig, SVG)

"""
    pdf(fig::Figure) :: HTTP.Response

Convert a figure to a PDF and wrap it inside an HTTP response.
"""
pdf(fig::Figure) :: HTTP.Response = response(fig, PDF)

"""
    html(fig::Figure) :: HTTP.Response

Convert a figure to HTML and wrap it inside an HTTP response.
"""
html(fig::Figure) :: HTTP.Response = response(fig, HTML)