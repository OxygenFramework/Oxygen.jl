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
        return "done"
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

# Raw channels are adopted like `sse_stream`: values become data frames, while
# `result(value)` ends the stream, writes `value` as the final frame (when it is
# not `nothing`), and is the buffered-fallback body for callers without a
# connection.
@get "/sse/raw" function()
    channel = Channel{Any}(4)
    put!(channel, Dict("raw" => 1))
    put!(channel, "raw text")
    close(channel)
    return channel
end

@get "/sse/raw_result" function()
    channel = Channel{Any}(4)
    put!(channel, Dict("raw" => 1))
    put!(channel, result(Dict("final" => 42)))
    return channel
end

@get "/sse/final_event" function()
    return sse_stream() do stream
        put!(stream, Dict("step" => 1))
        return SSEEvent(Dict("done" => true); event="done", id="3")
    end
end

@get "/sse/raw_final_event" function()
    channel = Channel{Any}(2)
    put!(channel, Dict("step" => 1))
    put!(channel, result(SSEEvent(Dict("done" => true); event="done")))
    return channel
end

@get "/sse/raw_producer" function()
    return Channel{Any}(2) do channel
        put!(channel, Dict("produced" => 1))
        put!(channel, SSEEvent(Dict("named" => 2); event="update", id="9"))
    end
end

@get "/sse/raw_error" function()
    return Channel{Any}(2) do channel
        put!(channel, Dict("ok" => true))
        error("raw route boom")
    end
end

# A long raw-channel stream for the disconnect test.
const RAW_DISCONNECTED = Ref(0)

@get "/sse/raw_long" function()
    channel = Channel{Any}(8)
    @async begin
        try
            for i in 1:100_000
                put!(channel, "tick $i " * ("payload " ^ 100))
                sleep(0.005)
            end
        finally
            RAW_DISCONNECTED[] += 1
        end
    end
    return channel
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
    @test length(frames) == 5
    @test JSON.parse(frames[1]) == Dict("i" => 1)
    @test JSON.parse(frames[2]) == [1, 2, 3]
    # Strings are streamed as-is, which is what `EventSource.data` expects.
    @test frames[3] == "plain text"
    @test JSON.parse(frames[4]) == Dict("via" => "emit")
    # The producer's return value is the final frame.
    @test frames[5] == "done"
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

@testset "raw channels stream frames on the live wire" begin
    response, body, frames = sse_lines("/sse/raw")
    @test response.status == 200
    @test HTTP.header(response, "Content-Type") == "text/event-stream"
    @test length(frames) == 2
    @test JSON.parse(frames[1]) == Dict("raw" => 1)
    @test frames[2] == "raw text"
end

@testset "the result marker writes the final frame" begin
    response, body, frames = sse_lines("/sse/raw_result")
    @test response.status == 200
    @test length(frames) == 2
    @test JSON.parse(frames[1]) == Dict("raw" => 1)
    @test JSON.parse(frames[2]) == Dict("final" => 42)
    @test occursin("final", body)
end

@testset "a returned SSEEvent controls the final frame" begin
    _, body, frames = sse_lines("/sse/final_event")
    @test length(frames) == 2
    @test JSON.parse(frames[1]) == Dict("step" => 1)
    @test JSON.parse(frames[2]) == Dict("done" => true)
    @test occursin("event: done", body)
    @test occursin("id: 3", body)
end

@testset "result(SSEEvent(...)) controls the final frame on a raw channel" begin
    _, body, frames = sse_lines("/sse/raw_final_event")
    @test length(frames) == 2
    @test JSON.parse(frames[2]) == Dict("done" => true)
    @test occursin("event: done", body)

    response = internalrequest(HTTP.Request("GET", "/sse/raw_final_event"))
    @test response.status == 200
    @test JSON.parse(String(response.body)) == Dict("done" => true)
end

@testset "internal requests get the marker value (or null)" begin
    response = internalrequest(HTTP.Request("GET", "/sse/raw_result"))
    @test response.status == 200
    @test JSON.parse(String(response.body)) == Dict("final" => 42)

    response = internalrequest(HTTP.Request("GET", "/sse/raw"))
    @test response.status == 200
    @test String(response.body) == "null"
end

@testset "SSEEvent control survives adoption" begin
    _, body, frames = sse_lines("/sse/raw_producer")
    @test length(frames) == 2
    @test frames[2] == "{\"named\":2}"
    @test occursin("event: update", body)
    @test occursin("id: 9", body)
end

@testset "raw channel producer errors become error frames" begin
    _, body, frames = sse_lines("/sse/raw_error")
    @test frames[1] == "{\"ok\":true}"
    @test occursin("event: error", body)
    @test occursin("raw route boom", body)
    @test !occursin("TaskFailedException", body)
end

@testset "internal requests surface raw channel producer errors" begin
    caught = try
        internalrequest(HTTP.Request("GET", "/sse/raw_error"); catch_errors=false)
        nothing
    catch error
        error
    end
    @test caught isa ErrorException
    @test occursin("raw route boom", sprint(showerror, caught))
end

@testset "disconnect releases a raw channel producer" begin
    before = RAW_DISCONNECTED[]
    io = HTTP.open("GET", "$SSE_URL/sse/raw_long")
    readline(io)  # wait until the first frame is on the wire
    close(io)     # hang up while the producer is still running

    deadline = time() + 15
    while time() < deadline && RAW_DISCONNECTED[] == before
        sleep(0.1)
    end
    @test RAW_DISCONNECTED[] > before
end

### Teardown ##################################################################

terminate()

end
