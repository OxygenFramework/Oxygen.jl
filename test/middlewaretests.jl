module MiddlewareTests
using Test
using HTTP
using Oxygen; @oxidise

invocation = []

function handler1(handler)
    return function(req::HTTP.Request)
        push!(invocation, 1)
        handler(req)
    end
end

function handler2(handler)
    return function(req::HTTP.Request)
        push!(invocation, 2)
        handler(req)
    end
end

function handler3(handler)
    return function(req::HTTP.Request)
        push!(invocation, 3)
        handler(req)
    end
end

@get "/multiply/{a}/{b}" function(req, a::Float64, b::Float64)
    return a * b 
end

r = internalrequest(HTTP.Request("GET", "/multiply/3/6"), middleware=[handler1, handler2, handler3], catch_errors=false)
@test r.status == 200
@test invocation == [1,2,3] # enusre the handlers are called in the correct order
@test text(r) == "18.0" 

empty!(invocation)

r = internalrequest(HTTP.Request("GET", "/multiply/3/6"), middleware=[handler3, handler1, handler2], catch_errors=false)
@test r.status == 200
@test invocation == [3,1,2] # enusre the handlers are called in the correct order
@test text(r) == "18.0" 


empty!(invocation)

r = internalrequest(HTTP.Request("GET", "/multiply/3/6"), middleware=[handler3, handler2, handler1], catch_errors=false)
@test r.status == 200
@test invocation == [3,2, 1] # enusre the handlers are called in the correct order
@test text(r) == "18.0" 

end