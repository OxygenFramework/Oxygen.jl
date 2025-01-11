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

@get "/injected" function(req, ctx::Context{Person})
    return json(ctx.payload)
end

@get "/kwarg-only" function(req; context)
    return json(context)
end

@get "/both-kwargs" function(; request::Request, context::Person)
    return json(context)
end

@get "/method-only" function()
    return json(context())
end

serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

@testset "null context tests" begin 
    try
        response = HTTP.get("$localhost/injected")
    catch e
        @test e isa HTTP.Exception
        @test e.status == 500
    end

    try
        response = HTTP.get("$localhost/method-only")
    catch e
        @test e isa HTTP.Exception
        @test e.status == 500
    end

    try
        response = HTTP.get("$localhost/kwarg-only")
    catch e
        @test e isa HTTP.Exception
        @test e.status == 500
    end

    @test context() isa Missing
end

terminate()

person = Person("John", 25)

serve(port=PORT, host=HOST, async=true, show_errors=true, show_banner=false, access_log=nothing, context=person)

@testset "context() tests" begin
    @test context() isa Person
    @test context() == person
end

@testset "standard get requests" begin 
    response = HTTP.get("$localhost/test")
    @test response.status == 200
    @test text(response) == "Hello World"
end

@testset "accessing injected context from a function handler" begin 
    response = HTTP.get("$localhost/injected")
    @test response.status == 200
    @test json(response, Person) == person
end

@testset "accessing injected context from kwargs" begin 
    response = HTTP.get("$localhost/kwarg-only")
    @test response.status == 200
    @test json(response, Person) == person
end

@testset "accessing injected context from kwargs (both request and context)" begin 
    response = HTTP.get("$localhost/both-kwargs")
    @test response.status == 200
    @test json(response, Person) == person
end

@testset "context() method only" begin 
    response = HTTP.get("$localhost/method-only")
    @test response.status == 200
    @test json(response, Person) == person
end

terminate()

end