module WGLGLMakieDemo

using Oxygen
using Oxygen: text
using WGLMakie
using WGLMakie.Makie: FigureLike
using Bonito, FileIO, Colors, HTTP
WGLMakie.activate!()

"""
Converts a Figure object to the designated MIME type and wraps it inside an HTTP response.
"""
function response(content::Union{FigureLike, App}, mime_type::MIME, status::Int, headers::Vector)
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

const HTML  = MIME"text/html"()

html(app::Bonito.App, status=200, headers=[]) :: HTTP.Response = response(app, HTML, status, headers)
html(plot::Makie.FigureLike, status=200, headers=[]) :: HTTP.Response = response(plot, HTML, status, headers)

get("/") do 
    text("home")
end

get("/plot") do 
    plt = heatmap(rand(50, 50))
    html(plt)
end

get("/page") do
    app = App() do session::Session
        hue_slider = Slider(0:360)
        color_swatch = DOM.div(class="h-6 w-6 p-2 m-2 rounded shadow")
        onjs(session, hue_slider.value, js"""function (hue){
            $(color_swatch).style.backgroundColor = "hsl(" + hue + ",60%,50%)"
        }""")
        return Row(hue_slider, color_swatch)
    end
    return html(app)
end

serve()

end