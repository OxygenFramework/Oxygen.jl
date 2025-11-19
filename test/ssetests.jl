module SSETests
using Test
using Dates
using HTTP
using ..Constants
using Oxygen; @oxidize

@get "/health" function()
    return text("I'm alive")
end

stream("/events/{name}") do stream::HTTP.Stream, name::String
    HTTP.setheader(stream, "Access-Control-Allow-Origin" => "*")
    HTTP.setheader(stream, "Access-Control-Allow-Methods" => "GET")
    HTTP.setheader(stream, "Content-Type" => "text/event-stream")
    HTTP.setheader(stream, "Cache-Control" => "no-cache")
    startwrite(stream)
    message = "Hello, $name"
    for _ in 1:5
        write(stream, format_sse_message(message))
        sleep(0.1)
    end
    closewrite(stream)
    return nothing
end


serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)


@testset "Stream Function tests" begin 

    HTTP.open("GET", "$localhost/events/john", headers=Dict("Connection" => "close")) do io
        while !eof(io)
            message = String(readavailable(io))
            if !isempty(message) && message != "null"
                @test message == "data: Hello, john\n\n"
            end
        end
    end

    HTTP.open("GET", "$localhost/events/matt", headers=Dict("Connection" => "close")) do io
        while !eof(io)
            message = String(readavailable(io))
            if !isempty(message) && message != "null"
                @test message == "data: Hello, matt\n\n"
            end
        end
    end
end

terminate()
println()


@testset "format_sse_message tests" begin
    @testset "basic functionality" begin
        @test format_sse_message("Hello") == "data: Hello\n\n"
        @test format_sse_message("Hello\nWorld") == "data: Hello\ndata: World\n\n"
    end

    @testset "optional parameters" begin
        @test format_sse_message("Hello", event="greeting") == "data: Hello\nevent: greeting\n\n"
        @test format_sse_message("Hello", id="1") == "data: Hello\nid: 1\n\n"
        @test format_sse_message("Hello", retry=1000) == "data: Hello\nretry: 1000\n\n"
    end

    @testset "newline in event or id" begin
        @test_throws ArgumentError format_sse_message("Hello", event="greeting\n")
        @test_throws ArgumentError format_sse_message("Hello", id="1\n")
    end

    @testset "retry is not positive" begin
        @test_throws ArgumentError format_sse_message("Hello", retry=0)
        @test_throws ArgumentError format_sse_message("Hello", retry=-1)
    end
end

end