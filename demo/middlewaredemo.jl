module MiddlewareDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3



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

function handler4(handler)
    return function(req::HTTP.Request)
        println("4")
        handler(req)
    end
end

math = router("math", middleware=[handler3])

# demonstrate how to use path params with regex patterns in HTTP v1.0+
@get math("/divide/{a:[0-9]+}/{b}") function (req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

@get math("/subtract/{a}/{b}", middleware=[handler4]) function (req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end


@get router("/power/{a}/{b}", middleware=[handler3]) function (req::HTTP.Request, a::Float64, b::Float64)
    return a ^ b
end

@get "/add/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a + b
end

serve([handler1, handler2])

# println(match(r"/divide/.*/.*", "/divide/34/nice"))

end