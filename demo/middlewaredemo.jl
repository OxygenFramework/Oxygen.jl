module MiddlewareDemo 

using Oxygen
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



"""

Middleware rules

All middleware is additive, any middleware defined at the application, router, our route level will get combined 
and get executed.

Regardless if set or not, Middleware will always get executed in the following order:

    application -> router -> route 

Well, what if we don't want previous layers of middleware to run? 
You set middleware=[], it clears all middleware at that layer and skips all layers that come before it.

For example, setting middleware=[] at the:
- application layer: clears the application layer
- router layer: clears the router layer and skips application layer
- route layer: clears the route layer and skips the application & router layer

"""

# case 1: no middleware setup,  uses the application middleware by default
@get "/add/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a + b
end

# case 1: no middleware is defined at any level -> use application middleware
@get router("/power/{a}/{b}") function (req::HTTP.Request, a::Float64, b::Float64)
    return a ^ b
end

math = router("/math", middleware=[handler3])

# case 2: middleware is cleared at route level so don't register any middleware
@get math("/cube/{a}", middleware=[]) function(req, a::Float64)
    return a * a * a
end

# case 3: router-level is empty & route-level is defined
other = router("/math", middleware=[])
@get other("/multiply/{a}/{b}", middleware=[handler3]) function (req::HTTP.Request, a::Float64, b::Float64)
    return a * b
end
# case 4 (both defined)
@get math("/divide/{a}/{b}", middleware=[handler4]) function(req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

# case 5: only router level is defined
@get math("/subtract/{a}/{b}") function(req::HTTP.Request, a::Float64, b::Float64)
    return a - b
end

# case 6: only route level middleware is defined
empty = router()
@get empty("/math/square/{a}", middleware=[handler3]) function(req, a::Float64)
    return a * a
end

serve(middleware=[handler1, handler2])

end
