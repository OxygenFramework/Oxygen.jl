module CustomSerializerDemo 

using Oxygen
using HTTP
using JSON

function middleware(handle)
    return function(req)
        try
            resp = handle(req)
            if resp isa HTTP.Messages.Response
                return resp
            end
            return HTTP.Response(200, [], body=JSON.json(resp))
        catch error
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The server encountered a problem")
        end
    end
end


@get "/hello" function (req::HTTP.Request)
    return "hello"
end

# disable default serializaiton
serve(serialize=false, middleware=[middleware])
end