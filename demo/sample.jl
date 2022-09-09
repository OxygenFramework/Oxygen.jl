module SampleDemo


include("../src/Oxygen.jl"); using .Oxygen
using HTTP
using JSON3

export terminate
# configdocs("/documentation", "/mycustomschema")

@route ["GET", "POST"] "/add/{a}/{b}" function(req, a::Float64, b::Float64)
    a + b
end


# @get "/stoptasks" function()
#     stoptasks()
# end

@get "/terminate" function()
    terminate()
end

# @staticfiles("content")

# @get router("/repeat", interval = 1.5) function()
#     println("repeat")
#     return "repeat"
# end

# serve(async=true)
# serveparallel()

serve()

end