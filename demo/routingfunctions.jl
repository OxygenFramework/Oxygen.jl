module FunctionsRoutingDemo

include("../src/Oxygen.jl")
using .Oxygen

using HTTP


get("/") do
    "hello"
end

math = router("/math", tags=["math"])

get(math("/add/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x + y
end

route(["POST"], math("/other/{x}/{y}")) do req, x::Int, y::Int
    x - y 
end

get(math("/multiply/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x * y
end

get("/get") do 
    "test"
end

put("/put") do 
    "put" 
end

patch("/patch") do 
    "patch" 
end

delete("/delete") do 
    "delete" 
end

# start the web server
serve()

end