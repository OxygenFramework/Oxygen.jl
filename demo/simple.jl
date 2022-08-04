module Simple 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3


@get "/hello" function()
    return Dict("msg" => 23423)
end


function handler(handler)
    return function(req)
        println("here")
        res = handler(req)

        if res isa HTTP.Response
            return res
        end

        HTTP.Response(200, [], body=String(JSON3.write(res))) 
    end
end

serve(handler)


end