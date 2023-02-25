module CustomSerializerDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3

function middleware(handle)
    return function(req)
        try
            resp = handle(req)
            if resp isa HTTP.Messages.Response
                return resp
            end
            return HTTP.Response(200, [], body=JSON3.write(resp))
        catch error
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The server encountered a problem")
        end
    end
end

greet_router = router("greet", middleware=[middleware])

@get greet_router("/hello") function (req::HTTP.Request)
    return "hello"
end

# disable default serializaiton
serve(serialize=false)

end