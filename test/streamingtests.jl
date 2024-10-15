module StreamingTests
using Test
using HTTP
using ..Constants
using Oxygen; @oxidise

function explicit_stream(stream::HTTP.Stream)
    # Set headers
    HTTP.setheader(stream, "Content-Type" => "text/plain")
    HTTP.setheader(stream, "Transfer-Encoding" => "chunked")

    # Start writing (if you need to send headers before the body)
    startwrite(stream)

    data = ["a", "b", "c"]
    for chunk in data
        write(stream, chunk)
    end

    # Close the stream to end the HTTP response properly
    closewrite(stream)
end

function implicit_stream(stream)
    explicit_stream(stream)
end

srouter = router("/stream")

@stream "/api/chunked/text" implicit_stream
stream(implicit_stream, srouter("/api/func/chunked/text"))
@post "/api/post/chunked/text" explicit_stream
@get "/api/error" implicit_stream

serve(port=PORT, host=HOST, async=true,  show_errors=false, show_banner=false, access_log=nothing)

@testset "StreamingChunksDemo Tests" begin

    @testset "macro stream handler" begin
        response = HTTP.get("$localhost/api/chunked/text", headers=Dict("Connection" => "close"))
        @test response.status == 200
        @test text(response) == "abc"
    end

    @testset "function stream handler" begin
        response = HTTP.get("$localhost/stream/api/func/chunked/text",  headers=Dict("Connection" => "close"))
        @test response.status == 200
        @test text(response) == "abc"
    end

    @testset "/api/post/chunked/text" begin
        response = HTTP.post("$localhost/api/post/chunked/text",  headers=Dict("Connection" => "close"))
        @test response.status == 200
        @test text(response) == "abc"
    end

    @testset "Can't setup implicit stream handler on regular routing macros & functions " begin
        try 
            response = HTTP.get("$localhost/api/error",  headers=Dict("Connection" => "close"))
            @test false
        catch e
            @test true #e isa HTTP.Exceptions.StatusError
        end
    end

end


terminate()
println()


end