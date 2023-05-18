module FunctionsRoutingDemo

include("../src/Oxygen.jl")
using .Oxygen

using HTTP


@get "/" function()
    "hello"
end

get("/add/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x + y
end

get("/multiply/{x}/{y}", function(request::HTTP.Request, x::Int, y::Int)
    x * y
end)

put("/put", () -> "put")
patch("/patch", () -> "patch")
delete("/delete", () -> "delete")

# start the web server
serve()

end