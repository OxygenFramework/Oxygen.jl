module Simple 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3

# demonstrate how to use path params with type definitions
@get "/divide/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end


@get "/hello" function()
    return Dict("msg" => 23423)
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

println(internalrequest(HTTP.Request("GET", "/divide/10/4")))
println(internalrequest(HTTP.Request("GET", "/divide/10/3"), handler1, handler2, handler3))

serve(handler1, handler2, handler3)

end