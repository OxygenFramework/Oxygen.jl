module SampleDemo


include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3

# configdocs("/documentation", "/mycustomschema")

@get "/add/{a}/{b}" function(req, a::Real, b::Real)
    a + b
end


# @get router("/repeat", interval = 1.5) function()
#     println("repeat")
#     return "repeat"
# end


serve()


end