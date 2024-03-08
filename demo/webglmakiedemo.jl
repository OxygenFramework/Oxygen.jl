module WGLGLMakieDemo
using Oxygen
using Oxygen: text, html
using WGLMakie
using WGLMakie.Makie: FigureLike
using Bonito, FileIO, Colors, HTTP
WGLMakie.activate!()

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