module Main 

using Oxygen

include("more.jl"); using .More

@get "/hello" function()
    return "hello world"
end


serve()

end 