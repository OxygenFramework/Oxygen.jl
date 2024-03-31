module MultiInstanceTests

using Test
using HTTP
using Oxygen
using ..Constants

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
app1.serve(port=PORT, async=true, show_errors=false, show_banner=false)
app2.serve(port=PORT, async=true, show_errors=false, show_banner=false)

@testset "testing unqiue instances" begin

    r = app1.internalrequest(HTTP.Request("GET", "/"))
    @test r.status == 200
    @test text(r) == "welcome to server #1"

    r = app2.internalrequest(HTTP.Request("GET", "/"))
    @test r.status == 200
    @test text(r) == "welcome to server #2"

end


@testset "testing add and subtract endpoints" begin

    # Test subtract endpoint on server #1
    r = app1.internalrequest(HTTP.Request("GET", "/subtract/10/5"))
    @test r.status == 200
    @test json(r)["answer"] == 5

    # Test add endpoint on server #2
    r = app2.internalrequest(HTTP.Request("GET", "/add/10/5"))
    @test r.status == 200
    @test json(r)["answer"] == 15

    # Test subtract endpoint with negative result on server #1
    r = app1.internalrequest(HTTP.Request("GET", "/subtract/5/10"))
    @test r.status == 200
    @test json(r)["answer"] == -5

    # Test add endpoint with negative numbers on server #2
    r = app2.internalrequest(HTTP.Request("GET", "/add/-10/-5"))
    @test r.status == 200
    @test json(r)["answer"] == -15

end

# clean it up
app1.terminate()
app2.terminate()

end