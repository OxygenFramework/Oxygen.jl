module SampleDemo


include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3

# configdocs("/documentation", "/mycustomschema")

@get "/add/{a}/{b}" function(req, a::Float64, b::Float64)
    a + b
end


@get "/stoptasks" function()
    stoptasks()
end

@get "/terminate" function()
    terminate()
end

@get router("/repeat", interval = 1.5) function()
    println("repeat")
    return "repeat"
end


serveparallel(async=true)


end