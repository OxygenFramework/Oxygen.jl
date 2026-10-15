module AppContextTests 
using Test
using HTTP
using ..Constants
using Oxygen; @oxidize

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

@testset "interruptible server wait" begin
    serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)
    service = CONTEXT[].service
    @test isopen(service)

    # wait(service) returns once the server is closed from another task
    waiter = @async wait(service)
    sleep(0.2)
    @test !istaskdone(waiter)
    terminate()
    wait(waiter)
    @test istaskdone(waiter)
    @test !isopen(service)

    # and it is interruptible at a safe point (JuliaLang/julia#46635)
    serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)
    service = CONTEXT[].service
    caught = Ref{Any}(nothing)
    waiter = @async try
        wait(service)
    catch e
        caught[] = e
    end
    sleep(0.2)
    schedule(waiter, InterruptException(); error=true)
    wait(waiter)
    @test caught[] isa InterruptException
    terminate()
end

@testset "server welcome banner" begin
    # the banner advertises the global prefix, the MCP endpoint and the explorer
    @test_logs (:info, r"Global path prefix: /api") (:info, r"MCP: .*/api/mcp") (:info, r"MCP Explorer: .*/api/docs/mcp") match_mode=:any begin
        Oxygen.Core.server_welcome(
            external_url = "http://127.0.0.1:$PORT",
            prefix = "/api",
            docs = true,
            metrics = true,
            mcp = true,
            parallel = false,
            docs_path = "/docs",
            mcp_path = "/mcp",
        )
    end
end

@testset "peeraddr_to_ip handles all address families" begin
    # an unavailable peer address falls back to the IPv4 unspecified address
    @test string(Oxygen.Core.peeraddr_to_ip(nothing)) == "0.0.0.0"
    @test string(Oxygen.Core.peeraddr_to_ip((ip = (127, 0, 0, 1),))) == "127.0.0.1"

    # a 16-octet address is rebuilt into 8 big-endian groups
    addr = (ip = (0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x00,
                  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,),)
    @test string(Oxygen.Core.peeraddr_to_ip(addr)) == "2001:db8::1"
end

@testset "serve-level stdio transport wiring" begin
    # a stub `start` hands back an unstarted server, keeping the test offline
    stub = (kwargs) -> HTTP.Server(handler = req -> HTTP.Response(200))

    # `stdio = true` without MCP is refused with a warning
    ctx = Oxygen.Core.ServerContext()
    @test_logs (:warn, r"Ignoring `stdio = true`") match_mode=:any begin
        Oxygen.Core.start_server(ctx; stdio=true, mcp=false, async=true, kwargs=Dict(), start=stub)
    end

    # with MCP enabled the stdio loop is started alongside the HTTP server
    ctx = Oxygen.Core.ServerContext()
    Oxygen.Core.start_server(ctx; stdio=true, mcp=true, async=true, kwargs=Dict(), start=stub)
    @test ctx.service.server[] isa HTTP.Server
end

end