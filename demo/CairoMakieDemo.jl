module CairoMakieDemo
import CairoMakie: heatmap
using Oxygen

get("/") do 
    html("<h1>welcome to the random plot api!</h1>")
end

# generate a random plot
get("/plot/png") do 
    fig, ax, pl = heatmap(rand(50, 50)) # or something
    png(fig)
end

get("/plot/svg") do 
    fig, ax, pl = heatmap(rand(50, 50)) # or something
    svg(fig)
end

get("/plot/pdf") do 
    fig, ax, pl = heatmap(rand(50, 50)) # or something
    pdf(fig)
end

get("/plot/html") do 
    fig, ax, pl = heatmap(rand(50, 50)) # or something
    html(fig)
end

serve()

end