module ExtractorTests

using Test
using HTTP
using ..Constants
using Oxygen; @oxidise

@get "/test" function(req)
    return "Hello World"
end

serve(port=PORT, host=HOST, async=true,  show_errors=false, show_banner=false)

r = internalrequest(HTTP.Request("GET", "/test"))
@test r.status == 200
@test text(r) == "Hello World"

terminate()

end
