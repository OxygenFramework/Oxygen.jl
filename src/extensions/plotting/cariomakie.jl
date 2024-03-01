using HTTP
using MIMEs
using .CairoMakie

export png_uri, svg_uri, pdf_uri, html_uri

# Here we list all our supported MIME types
PNG = MIME"image/png"()
SVG = MIME"image/svg+xml"()
PDF = MIME"application/pdf"()
HTML = MIME"text/html"()


"""
    generate_data_uri(fig::Figure, mime_type::MIME)

Generate a data URI for a given figure and MIME type. The figure is converted to the specified MIME type, 
then base64-encoded and formatted as a data URI.
"""
function generate_data_uri(fig::Figure, mime_type::MIME)
    io = IOBuffer()
    show(io, mime_type, fig)
    return "data:$(string(mime_type));base64,$(base64encode(take!(io)))"
end


"""
    png_uri(fig::Figure)

Generate a data URI for a given figure in PNG format.

# Arguments
- `fig::Figure`: The figure to convert.

# Returns
- A string representing the data URI of the figure in PNG format.
"""
png_uri(fig::Figure) = generate_data_uri(fig, PNG)

"""
    svg_uri(fig::Figure)

Generate a data URI for a given figure in SVG format.

# Arguments
- `fig::Figure`: The figure to convert.

# Returns
- A string representing the data URI of the figure in SVG format.
"""
svg_uri(fig::Figure) = generate_data_uri(fig, SVG)

"""
    pdf_uri(fig::Figure)

Generate a data URI for a given figure in PDF format.

# Arguments
- `fig::Figure`: The figure to convert.

# Returns
- A string representing the data URI of the figure in PDF format.
"""
pdf_uri(fig::Figure) = generate_data_uri(fig, PDF)

"""
    html_uri(fig::Figure)

Generate a data URI for a given figure in HTML format.

# Arguments
- `fig::Figure`: The figure to convert.

# Returns
- A string representing the data URI of the figure in HTML format.
"""
html_uri(fig::Figure) = generate_data_uri(fig, HTML)

