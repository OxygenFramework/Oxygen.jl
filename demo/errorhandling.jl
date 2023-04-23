module ErrorHandlingDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP

@get "/greet" function(req::HTTP.Request)
    return "hello world!"
end

@get "/bad" function(req::HTTP.Request)
    throw("whoops")
    "hello"
end


function errorcatcher(handle)
    function(req)
        try 
            println("here!")
            response = handle(req)
            println("response: $(String(response.body))")
            return response
        catch e 
            println("whoops there was an error")
            return HTTP.Response(200, "nice")
        end
    end
end


# start the web server
serve(middleware=[errorcatcher], error_handling=false)

end