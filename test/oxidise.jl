module OxidiseTest

using Test
using HTTP

using Oxygen; @oxidise

PORT = 6060

@get "/test" function(req)
    return "Hello World"
end

serve(async=true, port=PORT, show_errors=false)

r = internalrequest(HTTP.Request("GET", "/test"))
@test r.status == 200
@test text(r) == "Hello World"

terminate()

end
