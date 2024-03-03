module CairoMakieDemo
using CairoMakie: heatmap
using Oxygen: text # CairoMakie also exports text
using Oxygen

get("/") do 
    text("welcome to the random plot api!")
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