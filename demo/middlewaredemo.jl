module MiddlewareDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3

# demonstrate how to use path params with regex patterns in HTTP v1.0+
@get "/divide/{a:[0-9]+}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

function handler1(handler)
    return function(req::HTTP.Request)
        println("1")
        handler(req)
    end
end

function handler2(handler)
    return function(req::HTTP.Request)
        println("2")
        handler(req)
    end
end

function handler3(handler)
    return function(req::HTTP.Request)
        println("3")
        handler(req)
    end
end

serve(handler1, handler2, handler3)

end