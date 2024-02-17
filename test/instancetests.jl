module MultiInstanceTests

using Test
using HTTP
using Oxygen

# Setup the first app
app1 = instance()

app1.get("/") do 
    "welcome to server #1"
end

app1.get("/subtract/{a}/{b}") do req, a::Int, b::Int
    Dict("answer" => a - b) |> json
end

# Setup the second app
app2 = instance()

app2.get("/") do 
    "welcome to server #2"
end

app2.get("/add/{a}/{b}") do req, a::Int, b::Int
    Dict("answer" => a + b) |> json
end

 
# start both servers together
app1.serve(port=8001, async=true, show_errors=false)
app2.serve(port=8002, async=true, show_errors=false)

@testset "testing unqiue instances" begin

    r = app1.internalrequest(HTTP.Request("GET", "/"))
    @test r.status == 200
    @test text(r) == "welcome to server #1"

    r = app2.internalrequest(HTTP.Request("GET", "/"))
    @test r.status == 200
    @test text(r) == "welcome to server #2"

end

# clean it up
app1.terminate()
app2.terminate()

end