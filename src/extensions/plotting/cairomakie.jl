import HTTP
import .CairoMakie: Figure
import .Core.Util: html # import the html function from util so we can override it

export png, svg, pdf, html

# Here we list all our supported MIME types
const PNG   = MIME"image/png"()
const SVG   = MIME"image/svg+xml"()
const PDF   = MIME"application/pdf"()
const HTML  = MIME"text/html"()

"""
Converts a Figure object to the designated MIME type and wraps it inside an HTTP response.
"""
function response(fig::Figure, mime_type::MIME, status::Int, headers::Vector) :: HTTP.Response
    # Convert & load the figure into an IOBuffer
    io = IOBuffer()
    show(io, mime_type, fig)
    body = take!(io)
    
    # format the response
    resp = HTTP.Response(status, headers, body)
    HTTP.setheader(resp, "Content-Type" => string(mime_type))
    HTTP.setheader(resp, "Content-Length" => string(sizeof(body)))
    return resp
end

"""
    svg(fig::Figure) :: HTTP.Response

Convert a figure to an PNG and wrap it inside an HTTP response.
"""
png(fig::Figure, status=200, headers=[]) :: HTTP.Response = response(fig, PNG, status, headers)


"""
    svg(fig::Figure) :: HTTP.Response

Convert a figure to an SVG and wrap it inside an HTTP response.
"""
svg(fig::Figure, status=200, headers=[]) :: HTTP.Response = response(fig, SVG, status, headers)

"""
    pdf(fig::Figure) :: HTTP.Response

Convert a figure to a PDF and wrap it inside an HTTP response.
"""
pdf(fig::Figure, status=200, headers=[]) :: HTTP.Response = response(fig, PDF, status, headers)

"""
    html(fig::Figure) :: HTTP.Response

Convert a figure to HTML and wrap it inside an HTTP response.
"""
html(fig::Figure, status=200, headers=[]) :: HTTP.Response = response(fig, HTML, status, headers)