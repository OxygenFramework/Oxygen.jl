module Simple 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3


@get "/hello" function()
    return "hi"
end

serve()


end