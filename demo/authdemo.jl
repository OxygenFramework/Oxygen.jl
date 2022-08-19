module AuthDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP

@get "/divide/{a}/{b}" function(req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS"
]

# https://juliaweb.github.io/HTTP.jl/stable/examples/#Cors-Server
function CorsMiddleware(handler)
    return function(req::HTTP.Request)
        if HTTP.hasheader(req, "OPTIONS")
            return HTTP.Response(200, CORS_HEADERS)
        else 
            return handler(req)
        end
    end
end

function AuthMiddleware(handler)
    return function(req::HTTP.Request)
        # ** NOT an actual security check ** #
        if !HTTP.headercontains(req, "Authorization", "true")
            return HTTP.Response(403)
        else 
            return HTTP.Response(200, body=string(handler(req)))
        end
    end
end

# There is no hard limit on the number of middleware functions you can add
serve(middleware=[CorsMiddleware, AuthMiddleware])

end 