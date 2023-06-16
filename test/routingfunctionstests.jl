module RoutingFunctionsTests 
using Test
using HTTP
using JSON3
using StructTypes
using Sockets
using Dates 

include("../src/Oxygen.jl")
using .Oxygen

##### Setup Routes #####

inline = router("/inline")

get(inline("/add/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x + y
end
get("/add/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x + y
end

post(inline("/sub/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x - y
end
post("/sub/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x - y
end

put(inline("/power/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x ^ y
end
put("/power/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x ^ y
end

patch(inline("/mulitply/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x * y
end
patch("/mulitply/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x * y
end

delete(inline("/divide/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x / y
end
delete("/divide/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x / y
end

route(["GET"], inline("/route/add/{x}/{y}")) do request::HTTP.Request, x::Int, y::Int
    x + y
end
route(["GET"], "/route/add/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x + y
end

##### Begin tests #####


@testset "GET routing functions" begin 
    r = internalrequest(HTTP.Request("GET", "/inline/add/5/4"))
    @test r.status == 200
    @test text(r) == "9"

    r = internalrequest(HTTP.Request("GET", "/add/5/4"))
    @test r.status == 200
    @test text(r) == "9"

    r = internalrequest(HTTP.Request("GET", "/inline/route/add/5/4"))
    @test r.status == 200
    @test text(r) == "9"

    r = internalrequest(HTTP.Request("GET", "/route/add/5/4"))
    @test r.status == 200
    @test text(r) == "9"
end

@testset "POST routing functions" begin 
    r = internalrequest(HTTP.Request("POST", "/inline/sub/5/4"))
    @test r.status == 200
    @test text(r) == "1"

    r = internalrequest(HTTP.Request("POST", "/sub/5/4"))
    @test r.status == 200
    @test text(r) == "1"
end

@testset "PUT routing functions" begin 
    r = internalrequest(HTTP.Request("PUT", "/inline/power/5/4"))
    @test r.status == 200
    @test text(r) == "625"

    r = internalrequest(HTTP.Request("PUT", "/power/5/4"))
    @test r.status == 200
    @test text(r) == "625"
end

@testset "PATCH routing functions" begin 
    r = internalrequest(HTTP.Request("PATCH", "/inline/mulitply/5/4"))
    @test r.status == 200
    @test text(r) == "20"

    r = internalrequest(HTTP.Request("PATCH", "/mulitply/5/4"))
    @test r.status == 200
    @test text(r) == "20"
end

@testset "DELETE routing functions" begin 
    r = internalrequest(HTTP.Request("DELETE", "/inline/divide/5/4"))
    @test r.status == 200
    @test text(r) == "1.25"

    r = internalrequest(HTTP.Request("DELETE", "/divide/5/4"))
    @test r.status == 200
    @test text(r) == "1.25"
end

# clear any routes setup in this file
resetstate()

end