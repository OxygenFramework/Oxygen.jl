module SSEStreamTests

using Test
using HTTP
using JSON
using Oxygen; @oxidize
using ..Constants

### Registered routes ##########################################################

@get "/sse/data" function()
    return sse_stream() do stream
        put!(stream, Dict("i" => 1))
        put!(stream, [1, 2, 3])
        put!(stream, "plain text")
        emit(stream, Dict("via" => "emit"))
        return "ignored"
    end
end

struct SSEMetric
    name  :: String
    value :: Float64
end

@get "/sse/struct" function()
    return sse_stream() do stream
        put!(stream, SSEMetric("cpu", 0.5))
        put!(stream, (a=1, b=[true, false]))
    end
end

@get "/sse/values" function()
    return sse_stream() do stream
        put!(stream, 2)
        put!(stream, nothing)
        put!(stream, true)
    end
end

# `JSON.lower` custom serialization is honored.
struct Wrapped
    value :: Int
end

JSON.lower(wrapper::Wrapped) = Dict("wrapped" => wrapper.value)

@get "/sse/lower" function()
    return sse_stream() do stream
        put!(stream, Wrapped(9))
    end
end

# A value with no JSON representation; normalizing this yield fails.
struct Unserializable end

JSON.lower(::Unserializable) = error("no JSON form")

@get "/sse/bad_yield" function()
    return sse_stream() do stream
        put!(stream, Unserializable())
        return "never"
    end
end

@get "/sse/event" function()
    return sse_stream() do stream
        put!(stream, SSEEvent(Dict("a" => 1); event="update", id="7", retry=1000))
        put!(stream, SSEEvent("raw text"))
    end
end

@get "/sse/error" function()
    return sse_stream() do stream
        put!(stream, Dict("ok" => true))
        error("mid-stream boom")
    end
end

# `@stream` handlers receive the raw HTTP.Stream and can return a stream too.
@stream "/sse/chunked" function(stream::HTTP.Stream)
    return sse_stream() do source
        put!(source, Dict("from" => "stream handler"))
    end
end

# Buffered fallback for requests without a live connection (internalrequest).
@get "/sse/buffered" function()
    return sse_stream() do stream
        put!(stream, Dict("dropped" => true))
        return Dict("final" => 42)
    end
end

# A long stream for the disconnect test; the payload is fat on purpose so the
# server's write fails (rather than buffers) shortly after the client hangs up.
const DISCONNECTED = Ref(0)

@get "/sse/long" function()
    return sse_stream() do stream
        try
            for i in 1:100_000
                put!(stream, "tick $i " * ("payload " ^ 100))
                sleep(0.005)
            end
        finally
            DISCONNECTED[] += 1
        end
    end
end

### Request helpers ###########################################################

const SSE_PORT = PORT + 4
const SSE_URL = "http://$HOST:$SSE_PORT"

serve(port=SSE_PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing)

function sse_lines(path)::Tuple{HTTP.Response,String,Vector{String}}
    response = HTTP.get("$SSE_URL$path")
    body = String(response.body)
    frames = String[strip(line[6:end]) for line in split(body, '\n')
                    if startswith(line, "data:")]
    return response, body, frames
end

### Tests #####################################################################

@testset "arbitrary objects serialize into data frames" begin
    response, body, frames = sse_lines("/sse/data")
    @test response.status == 200
    @test HTTP.header(response, "Content-Type") == "text/event-stream"
    @test length(frames) == 4
    @test JSON.parse(frames[1]) == Dict("i" => 1)
    @test JSON.parse(frames[2]) == [1, 2, 3]
    # Strings are streamed as-is, which is what `EventSource.data` expects.
    @test frames[3] == "plain text"
    @test JSON.parse(frames[4]) == Dict("via" => "emit")
    # The producer's return value is not streamed.
    @test !occursin("ignored", body)
end

@testset "custom structs and named tuples serialize" begin
    _, _, frames = sse_lines("/sse/struct")
    @test JSON.parse(frames[1]) == Dict("name" => "cpu", "value" => 0.5)
    @test JSON.parse(frames[2]) == Dict("a" => 1, "b" => [true, false])
end

@testset "non-object values serialize as JSON" begin
    _, _, frames = sse_lines("/sse/values")
    @test frames == ["2", "null", "true"]
end

@testset "JSON.lower is honored" begin
    _, _, frames = sse_lines("/sse/lower")
    @test JSON.parse(frames[1]) == Dict("wrapped" => 9)
end

@testset "unserializable yields end the stream with an error frame" begin
    _, body, frames = sse_lines("/sse/bad_yield")
    @test length(frames) == 1
    @test occursin("no JSON form", JSON.parse(frames[1])["error"])
    @test occursin("event: error", body)
end

@testset "SSEEvent controls event name, id and retry" begin
    _, body, frames = sse_lines("/sse/event")
    @test frames[1] == "{\"a\":1}"
    @test frames[2] == "raw text"
    @test occursin("event: update", body)
    @test occursin("id: 7", body)
    @test occursin("retry: 1000", body)
end

@testset "mid-stream errors emit an error frame" begin
    _, body, frames = sse_lines("/sse/error")
    @test frames[1] == "{\"ok\":true}"
    @test occursin("event: error", body)
    @test occursin("mid-stream boom", body)
end

@testset "@stream handlers can return a stream" begin
    response, _, frames = sse_lines("/sse/chunked")
    @test response.status == 200
    @test length(frames) == 1
    @test JSON.parse(frames[1]) == Dict("from" => "stream handler")
end

@testset "internal requests buffer the stream to its final value" begin
    response = internalrequest(HTTP.Request("GET", "/sse/buffered"))
    @test response.status == 200
    @test JSON.parse(String(response.body)) == Dict("final" => 42)
end

@testset "disconnect releases the producer" begin
    before = DISCONNECTED[]
    io = HTTP.open("GET", "$SSE_URL/sse/long")
    readline(io)  # wait until the first frame is on the wire
    close(io)     # hang up while the producer is still running

    deadline = time() + 15
    while time() < deadline && DISCONNECTED[] == before
        sleep(0.1)
    end
    @test DISCONNECTED[] > before
end

### Teardown ##################################################################

terminate()

end
