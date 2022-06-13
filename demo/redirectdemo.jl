module RedirectDemo 
using HTTP

include("../src/Oxygen.jl")
using .Oxygen

@get "/a" function()
    return "first endpoint"
end


@get "/b" function()
    "b endpoint"
    # return HTTP.Response(308, ["Location" => "/a"])
end

@staticfiles "content"

serve()

end 