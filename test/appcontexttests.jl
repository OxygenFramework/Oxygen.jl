module AppContextTests 
using Test
using HTTP
using ..Constants
using Oxygen; @oxidise

struct Person
    name::String
    age::Int
end

@get "/test" function(req)
    return "Hello World"
end

@get "/ctx" function(req)
    return json(context())
end

@get "/injected" function(req, ctx::Context{Person})
    return json(ctx.context)
end

serve(port=PORT, host=HOST, async=true,  show_errors=false, show_banner=false, access_log=nothing)

terminate()

@testset "null context tests" begin
    @test context() isa Missing
    @test context() === missing
end

terminate()

person = Person("John", 25)

serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing, context=person)

@testset "standard get requests" begin 
    response = HTTP.get("$localhost/test")
    @test response.status == 200
    @test text(response) == "Hello World"
end

@testset "accessing context from a function handler" begin 
    response = HTTP.get("$localhost/ctx")
    @test response.status == 200
    @test json(response, Person) == person
end

@testset "accessing injected context from a function handler" begin 
    response = HTTP.get("$localhost/injected")
    @test response.status == 200
    @test json(response, Person) == person
end

@testset "Non-null context tests" begin
    @test context() isa Person
    @test context() === person
end

terminate()

end