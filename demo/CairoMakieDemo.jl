module CairoMakieDemo

using CairoMakie
using Oxygen

println(png)

# generate a random plot
get("/plot") do 
    fig, ax, pl = heatmap(rand(50, 50)) # or something
    png(fig)
end

serve()

end