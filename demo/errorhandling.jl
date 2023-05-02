module ErrorHandlingDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP

@get "/" function(req::HTTP.Request)
    return "hello world!"
end

@get "/bad" function(req::HTTP.Request)
    throw("whoops")
    "hello"
end


function errorcatcher(handle)
    function(req)
        try 
            response = handle(req)
            return response
        catch e 
            return HTTP.Response(500, "here's a custom error response")
        end
    end
end


# start the web server
serve(middleware=[errorcatcher], catch_errors=false)

end