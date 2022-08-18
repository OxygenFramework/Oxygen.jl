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

# case 1: no middleware is defined at any level -> use global middleware
@get router("/power/{a}/{b}") function (req::HTTP.Request, a::Float64, b::Float64)
    return a ^ b
end

math = router("/math", middleware=[handler3])

# case 2: router & route level is defined -> ignore global middleware + combine router & route middleware 
@get math("/divide/{a}/{b}", middleware=[handler4]) function(req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

# case 3: only router level is defined -> ignore global middleware + only register router level 
@get math("/subtract/{a}/{b}") function(req::HTTP.Request, a::Float64, b::Float64)
    return a - b
end

# case 4: only route level is defined -> combine global + route level middleware
empty = router()
@get empty("/cube/{a}", middleware=[handler3]) function(req, a::Float64)
    return a * a * a
end

# demonstrate how to bypass all global middleware
@get router("/multiply/{a}/{b}", middleware=[]) function (req::HTTP.Request, a::Float64, b::Float64)
    return a * b
end

# uses the global middleware by default
@get "/add/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a + b
end

serveparallel(middleware=[handler1, handler2])

end