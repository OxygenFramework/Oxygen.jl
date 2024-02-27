module CorsDemo

using Oxygen
using HTTP

allowed_origins = [ "Access-Control-Allow-Origin" => "*" ]

cors_headers = [
    allowed_origins...,
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST"
]

function CorsHandler(handle)
    return function (req::HTTP.Request)
        # return headers on OPTIONS request
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, cors_headers)
        else
            r = handle(req)
            append!(r.headers, allowed_origins)
            return r
        end
    end
end

get("/") do
   text("hello world")
end

# more code here
serve(middleware=[CorsHandler])

end