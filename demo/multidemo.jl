module MultiInstanceDemo

using Oxygen
using HTTP

# Setup the first app
app1 = instance()

app1.get("/") do 
    "welcome to server #1"
end

app1.@get("/subtract/{a}/{b}") do req, a::Int, b::Int
    ("answer" => a - b)
end

# Setup the second app
app2 = instance()

app2.get("/") do 
    "welcome to server #2"
end

app2.@get("/add/{a}/{b}") do req, a::Int, b::Int
    ("answer" => a + b)
end

try 
    # start both servers together
    app1.serve(port=8001, async=true)
    app2.serve(port=8002)
finally
    # clean it up
    app1.terminate()
    app2.terminate()
end

end