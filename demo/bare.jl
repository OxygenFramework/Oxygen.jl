module Bare 

include("../src/Oxygen.jl")
using .Oxygen


@get "greet" function()
    return "hello world"
end


serve()

end