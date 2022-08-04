module Simple 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using JSON3




# demonstrate how to use path params with type definitions
@get "/divide/{a:[0-9]{1}}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

internalrequest(HTTP.Request("GET", "/divide/10/3"))

# # @get "/hello" function()
# #     return Dict("msg" => 23423)
# # end

# function handler(handler)
#     return function(req)
#         res = handler(req)

#         if res isa HTTP.Response
#             return res
#         end

#         HTTP.Response(200, [], body=String(JSON3.write(res))) 
#     end
# end

# serve()

end