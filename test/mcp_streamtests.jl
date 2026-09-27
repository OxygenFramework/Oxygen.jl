module MCPStreamTests

using Test
using HTTP
using JSON
using Oxygen; @oxidize
using ..Constants

const MCP = Oxygen.Core.MCP

### Registered tools ##########################################################

# Surface B: the do-block owns the channel and returns the final result.
@tool "Streams auto-numbered steps" Dict(:count => "number of steps") function stream_steps(count::Int)
    return mcp_stream() do stream
        for i in 1:count
            put!(stream, "step $i")
        end
        return "finished $count steps"
    end
end

@tool "Streams explicit progress" Dict(:count => "number of steps") function stream_explicit(count::Int)
    return mcp_stream() do stream
        for i in 1:count
            put!(stream, progress(i, count; message="step $i"))
        end
        return "done"
    end
end

@tool "Streams mixed yield types" Dict() function stream_mixed()
    return mcp_stream() do stream
        put!(stream, "first")
        put!(stream, 2)        # explicit progress value
        put!(stream, nothing)  # heartbeat
        put!(stream, "last")
        return "mixed"
    end
end

@tool "Streams from an injected handle" Dict(:count => "number of steps") function stream_injected(count::Int; stream)
    for i in 1:count
        emit(stream, "emit $i")
    end
    return "emitted $count"
end

@tool "Streams a structured message" Dict(:message => "the message") function stream_structured_message(message::String)
    return mcp_stream() do stream
        put!(stream, Dict("level" => "info", "message" => message))
        return "sent"
    end
end

@tool "Quiet streaming handler" Dict(:value => "a value") function stream_quiet(value::Int)
    return mcp_stream() do stream
        return value + 1
    end
end

@tool "Quiet buffered handler" Dict(:value => "a value") function plain_quiet(value::Int)
    return value + 1
end

@tool "Quiet injected handler" Dict(:value => "a value") function stream_quiet_injected(value::Int; stream)
    return value + 2
end

@tool "Streams a structured result" Dict(:name => "the name") function stream_structured(name::String)
    return mcp_stream() do stream
        put!(stream, "working")
        return Dict("name" => name, "nested" => Dict("ok" => true))
    end
end

@tool "Emits from a child task" Dict() function stream_child_task()
    return mcp_stream() do stream
        task = @async put!(stream, "from child")
        wait(task)
        return "child done"
    end
end

@tool "Errors before streaming" Dict() function stream_error_before()
    return mcp_stream() do stream
        error("early boom")
    end
end

@tool "Errors after streaming" Dict() function stream_error_after()
    return mcp_stream() do stream
        put!(stream, "one")
        error("late boom")
    end
end

# A value with no JSON representation; normalizing this yield fails.
struct Unserializable end

JSON.lower(::Unserializable) = error("no JSON form")

@tool "Streams an unserializable yield" Dict() function stream_bad_yield()
    return mcp_stream() do stream
        put!(stream, Unserializable())
        return "never"
    end
end

# A long stream for the disconnect test; the payload is fat on purpose so the
# server's write fails (rather than buffers) shortly after the client hangs up.
const DISCONNECTED = Ref(0)

@tool "Long running stream" Dict() function stream_long()
    return mcp_stream() do stream
        try
            for i in 1:100_000
                put!(stream, "tick $i " * ("payload " ^ 100))
                sleep(0.005)
            end
        finally
            DISCONNECTED[] += 1
        end
        return "done"
    end
end

### Request helpers ###########################################################

const STREAM_PORT = PORT + 3
const STREAM_URL = "http://$HOST:$STREAM_PORT/mcp"

# JSON posts share a client so repeated buffered calls stay cheap; the socket
# is closed by the server (`Connection: close`), so pooling is harmless.
const STREAM_CLIENT = HTTP.Client()

function call_payload(name::String, arguments::AbstractDict;
                      token="tok-1", meta_extra=Dict{String,Any}(), id=1, modern=true)
    meta = modern ? Dict{String,Any}(
        "io.modelcontextprotocol/protocolVersion" => MCP.PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => Dict{String,Any}(),
    ) : Dict{String,Any}()
    token === nothing || (meta["progressToken"] = token)
    merge!(meta, meta_extra)
    params = Dict{String,Any}("name" => name, "arguments" => arguments)
    isempty(meta) || (params["_meta"] = meta)
    return Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "method" => "tools/call", "params" => params)
end

function call_headers(name::String; accept="application/json, text/event-stream", modern=true)
    headers = ["Content-Type" => "application/json", "Accept" => accept]
    if modern
        append!(headers, [
            "MCP-Protocol-Version" => MCP.PROTOCOL_VERSION,
            "Mcp-Method" => "tools/call",
            "Mcp-Name" => name,
        ])
    end
    return headers
end

function json_call(payload; headers=call_headers(payload["params"]["name"]))::HTTP.Response
    return HTTP.request("POST", STREAM_URL, headers, JSON.json(payload);
                        status_exception=false, client=STREAM_CLIENT)
end

# Read the reply as SSE `data:` frames. The do-block form returns the final
# `HTTP.Response`, so tests can also assert the negotiated content type. The
# request body is written first and half-closed, then the response is read
# while it is still being produced.
function sse_call(payload; headers=call_headers(payload["params"]["name"]))::Tuple{HTTP.Response,Vector{Any}}
    frames = Any[]
    response = HTTP.open("POST", STREAM_URL, headers; client=HTTP.Client()) do io
        write(io, JSON.json(payload))
        HTTP.closewrite(io)
        for line in eachline(io)
            startswith(line, "data:") || continue
            push!(frames, JSON.parse(strip(line[6:end])))
        end
    end
    return response, frames
end

parsebody(response::HTTP.Response) = JSON.parse(String(response.body))

serve(port=STREAM_PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing)

### HTTP streaming tests ######################################################

@testset "registry records the injected stream" begin
    tool = CONTEXT[].mcp.tools["stream_injected"]
    @test tool.has_stream
    schema = MCP.inputschema(tool)
    @test !haskey(schema["properties"], "stream")
    @test schema["required"] == ["count"]

    # Surface B handlers do not declare `; stream`; the channel is the return value.
    @test CONTEXT[].mcp.tools["stream_steps"].has_stream == false
end

@testset "progress frames precede the final result" begin
    payload = call_payload("stream_steps", Dict("count" => 3); id=11)
    response, frames = sse_call(payload)

    @test response.status == 200
    @test startswith(HTTP.header(response, "Content-Type"), "text/event-stream")
    @test HTTP.header(response, "Cache-Control") == "no-cache"
    @test HTTP.header(response, "X-Accel-Buffering") == "no"
    @test length(frames) == 4

    progresses = [frame["params"] for frame in frames[1:3]]
    @test all(frame -> frame["method"] == "notifications/progress", frames[1:3])
    @test [p["progress"] for p in progresses] == [1.0, 2.0, 3.0]
    @test [p["message"] for p in progresses] == ["step 1", "step 2", "step 3"]
    @test all(p -> p["progressToken"] == "tok-1", progresses)

    final = frames[4]
    @test final["id"] == 11
    @test final["result"]["content"][1]["text"] == "finished 3 steps"
    @test final["result"]["isError"] == false
    @test final["result"]["resultType"] == "complete"
    @test final["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "Oxygen"
end

@testset "quiet calls stay application/json" begin
    for name in ("stream_quiet", "stream_quiet_injected")
        payload = call_payload(name, Dict("value" => 1))
        response = json_call(payload; headers=call_headers(name))
        @test startswith(HTTP.header(response, "Content-Type"), "application/json")
        @test parsebody(response)["result"]["content"][1]["text"] == (name == "stream_quiet" ? "2" : "3")
    end

    # The same result serializes to the same bytes as the buffered path.
    plain = call_payload("plain_quiet", Dict("value" => 1); id=12)
    streamed = call_payload("stream_quiet", Dict("value" => 1); id=12)
    @test json_call(plain; headers=call_headers("plain_quiet")).body ==
          json_call(streamed; headers=call_headers("stream_quiet")).body
end

@testset "Accept: application/json drops notifications" begin
    payload = call_payload("stream_steps", Dict("count" => 2))
    response = json_call(payload; headers=call_headers("stream_steps"; accept="application/json"))
    body = String(response.body)
    @test startswith(HTTP.header(response, "Content-Type"), "application/json")
    @test !occursin("notifications/progress", body)
    @test JSON.parse(body)["result"]["content"][1]["text"] == "finished 2 steps"
end

@testset "no progress token drains and returns JSON" begin
    payload = call_payload("stream_steps", Dict("count" => 2); token=nothing)
    response = json_call(payload; headers=call_headers("stream_steps"))
    @test startswith(HTTP.header(response, "Content-Type"), "application/json")
    @test parsebody(response)["result"]["content"][1]["text"] == "finished 2 steps"
end

@testset "auto-increment is monotonic across mixed yields" begin
    payload = call_payload("stream_mixed", Dict())
    _, frames = sse_call(payload)
    @test length(frames) == 5
    @test [f["params"]["progress"] for f in frames[1:4]] == [1.0, 2.0, 3.0, 4.0]
    @test frames[1]["params"]["message"] == "first"
    @test !haskey(frames[2]["params"], "message")  # explicit Real
    @test !haskey(frames[3]["params"], "message")  # heartbeat
    @test frames[4]["params"]["message"] == "last"
    @test frames[5]["result"]["content"][1]["text"] == "mixed"
end

@testset "explicit progress carries total and message" begin
    payload = call_payload("stream_explicit", Dict("count" => 3))
    _, frames = sse_call(payload)
    @test length(frames) == 4
    for (i, frame) in enumerate(frames[1:3])
        @test frame["params"]["progress"] == Float64(i)
        @test frame["params"]["total"] == 3.0
        @test frame["params"]["message"] == "step $i"
    end
end

@testset "final result is the do-block return value" begin
    payload = call_payload("stream_structured", Dict("name" => "ox"))
    _, frames = sse_call(payload)
    final = frames[end]
    @test final["result"]["structuredContent"]["name"] == "ox"
    @test final["result"]["structuredContent"]["nested"]["ok"] == true
end

@testset "injected handle streams (Surface A)" begin
    payload = call_payload("stream_injected", Dict("count" => 2))
    _, frames = sse_call(payload)
    @test length(frames) == 3
    @test [f["params"]["message"] for f in frames[1:2]] == ["emit 1", "emit 2"]
    @test frames[3]["result"]["content"][1]["text"] == "emitted 2"
end

@testset "child tasks emit through the lexically captured handle" begin
    payload = call_payload("stream_child_task", Dict())
    _, frames = sse_call(payload)
    @test length(frames) == 2
    @test frames[1]["params"]["message"] == "from child"
    @test frames[2]["result"]["content"][1]["text"] == "child done"
end

@testset "error before the first event returns JSON" begin
    payload = call_payload("stream_error_before", Dict())
    response = json_call(payload; headers=call_headers("stream_error_before"))
    @test startswith(HTTP.header(response, "Content-Type"), "application/json")
    result = parsebody(response)["result"]
    @test result["isError"] == true
    @test occursin("early boom", result["content"][1]["text"])

    # Also without a token.
    payload = call_payload("stream_error_before", Dict(); token=nothing)
    response = json_call(payload; headers=call_headers("stream_error_before"))
    @test parsebody(response)["result"]["isError"] == true
end

@testset "error after an event ends the SSE stream with isError" begin
    payload = call_payload("stream_error_after", Dict())
    response, frames = sse_call(payload)
    @test startswith(HTTP.header(response, "Content-Type"), "text/event-stream")
    @test length(frames) == 2
    @test frames[1]["params"]["message"] == "one"
    @test frames[2]["result"]["isError"] == true
    @test occursin("late boom", frames[2]["result"]["content"][1]["text"])
end

@testset "unserializable yields become error results" begin
    # The failure is the first event, so the reply stays JSON even when the
    # request opted into SSE.
    payload = call_payload("stream_bad_yield", Dict())
    response = json_call(payload; headers=call_headers("stream_bad_yield"))
    body = String(response.body)
    @test startswith(HTTP.header(response, "Content-Type"), "application/json")
    @test !occursin("data:", body)
    result = JSON.parse(body)["result"]
    @test result["isError"] == true
    @test occursin("no JSON form", result["content"][1]["text"])

    payload = call_payload("stream_bad_yield", Dict(); token=nothing)
    response = json_call(payload; headers=call_headers("stream_bad_yield"))
    @test parsebody(response)["result"]["isError"] == true
end

@testset "arbitrary yields are JSON-encoded into the progress message" begin
    payload = call_payload("stream_structured_message", Dict("message" => "hello"))
    _, frames = sse_call(payload)
    @test length(frames) == 2
    @test frames[1]["method"] == "notifications/progress"
    @test frames[1]["params"]["progress"] == 1.0
    # Handlers that want a custom notification shape of their own can yield a
    # dict/tuple and let the client parse it out of the message.
    @test JSON.parse(frames[1]["params"]["message"]) == Dict("level" => "info", "message" => "hello")
    @test frames[2]["result"]["content"][1]["text"] == "sent"
end

@testset "legacy path streams without the modern envelope" begin
    payload = call_payload("stream_steps", Dict("count" => 2);
                           token="tok-legacy", modern=false, id=13)
    _, frames = sse_call(payload; headers=call_headers("stream_steps"; modern=false))
    @test length(frames) == 3
    @test all(f -> f["params"]["progressToken"] == "tok-legacy", frames[1:2])
    @test frames[3]["id"] == 13
    @test frames[3]["result"]["content"][1]["text"] == "finished 2 steps"
    @test !haskey(frames[3]["result"], "resultType")
end

@testset "Accept negotiation for the SSE upgrade" begin
    accept(header) = MCP.accepts_event_stream(HTTP.Request("POST", "/", ["Accept" => header]))

    @test accept("application/json, text/event-stream")
    @test accept("text/event-stream")
    @test accept("text/*")
    @test accept("*/*")
    @test accept("text/event-stream;q=0.5")
    # An explicit refusal wins over any wildcard or listed media type.
    @test !accept("application/json")
    @test !accept("text/event-stream;q=0")
    @test !accept("text/event-stream;q=0, */*")
    @test !MCP.accepts_event_stream(HTTP.Request("POST", "/"))
end

@testset "modern validation runs before any streaming" begin
    payload = call_payload("stream_steps", Dict("count" => 2))
    # Modern _meta without the mirrored headers: rejected before a frame is written.
    response = json_call(payload; headers=["Content-Type" => "application/json",
                                           "Accept" => "application/json, text/event-stream"])
    @test response.status == 400
    @test parsebody(response)["error"]["code"] == MCP.MCP_HEADER_MISMATCH
end

@testset "concurrent streams are isolated" begin
    function call(token, id)
        payload = call_payload("stream_steps", Dict("count" => 2); token=token, id=id)
        return sse_call(payload)
    end

    results = Vector{Any}(undef, 2)
    @sync begin
        @async results[1] = call("tok-a", 21)
        @async results[2] = call("tok-b", 22)
    end

    for (index, token) in enumerate(("tok-a", "tok-b"))
        _, frames = results[index]
        @test length(frames) == 3
        @test all(f -> f["params"]["progressToken"] == token, frames[1:2])
        @test [f["params"]["progress"] for f in frames[1:2]] == [1.0, 2.0]
    end
end

@testset "disconnect mid-stream releases the producer" begin
    before = DISCONNECTED[]
    payload = call_payload("stream_long", Dict(); id=31)
    io = HTTP.open("POST", STREAM_URL, call_headers("stream_long"))
    write(io, JSON.json(payload))
    HTTP.closewrite(io)
    seen = 0
    for line in eachline(io)
        startswith(line, "data:") || continue
        seen += 1
        seen >= 2 && break
    end
    close(io)  # hang up while the producer is still running

    deadline = time() + 15
    while time() < deadline && DISCONNECTED[] == before
        sleep(0.1)
    end
    @test DISCONNECTED[] > before
end

### stdio transport ###########################################################

@testset "stdio interleaves notifications before the response" begin
    payload = call_payload("stream_steps", Dict("count" => 2); id=7)
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json(payload) * "\n"), output=output)
    lines = [JSON.parse(line) for line in split(strip(String(take!(output))), "\n")]
    @test length(lines) == 3
    @test lines[1]["method"] == "notifications/progress"
    @test lines[2]["method"] == "notifications/progress"
    @test lines[3]["id"] == 7
    @test lines[3]["result"]["content"][1]["text"] == "finished 2 steps"
end

@testset "stdio drops notifications without a token" begin
    payload = call_payload("stream_steps", Dict("count" => 2); token=nothing, id=8)
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json(payload) * "\n"), output=output)
    lines = [JSON.parse(line) for line in split(strip(String(take!(output))), "\n")]
    @test length(lines) == 1
    @test lines[1]["id"] == 8
end

@testset "stdio streams the legacy path too" begin
    payload = call_payload("stream_steps", Dict("count" => 2); token="tok-stdio", modern=false, id=9)
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json(payload) * "\n"), output=output)
    lines = [JSON.parse(line) for line in split(strip(String(take!(output))), "\n")]
    @test length(lines) == 3
    @test lines[1]["params"]["progressToken"] == "tok-stdio"
    @test !haskey(lines[3]["result"], "resultType")
end

### Engine unit tests #########################################################

@testset "bounded channel backpressure" begin
    @test MCP.STREAM_BUFFER_SIZE == 64

    stream = MCP.mcp_stream(ch -> begin
        for i in 1:5
            put!(ch, "step $i")
        end
        return "done"
    end; csize=2)
    @test stream.channel.sz_max == 2
    sleep(0.2)
    @test isready(stream)  # the producer is parked on the full buffer

    events = collect(stream)
    @test length(events) == 6
    @test [e.message for e in events[1:5]] == ["step $i" for i in 1:5]
    @test events[6] isa MCP.FinalEvent
    @test events[6].value == "done"
end

@testset "emit is a no-op without a token" begin
    stream = MCP.MCPStream(4; managed=true)
    MCP.emit(stream, "dropped")
    @test !isready(stream.channel)
end

@testset "cancellation releases a blocked producer" begin
    finished = Ref(false)
    stream = MCP.mcp_stream(ch -> begin
        try
            for i in 1:10_000
                put!(ch, "tick $i")
            end
        finally
            finished[] = true
        end
        return "done"
    end; csize=2)
    sleep(0.1)
    MCP.cancel_stream!(stream)

    deadline = time() + 5
    while time() < deadline && !finished[]
        sleep(0.05)
    end
    @test finished[]
    @test_throws MCP.MCPCancelled MCP.check_cancelled(stream)
    @test_throws MCP.MCPCancelled MCP.emit(stream, "late")
end

@testset "explicit progress must increase" begin
    stream = MCP.MCPStream(4; token="tok", managed=true)
    MCP.emit(stream, MCP.progress(2, 5; message="two"))
    @test_throws ArgumentError MCP.emit(stream, MCP.progress(1, 5))
    MCP.emit(stream, "next")  # auto-increments above 2
    @test take!(stream.channel).progress == 2.0
    @test take!(stream.channel).progress == 3.0
end

@testset "serialize_event opt-in gates" begin
    @test MCP.serialize_event(nothing, MCP.progress(1)) === nothing
    @test MCP.serialize_event("tok", MCP.progress(1, 4; message="go")) == Dict{String,Any}(
        "jsonrpc" => "2.0",
        "method" => "notifications/progress",
        "params" => Dict{String,Any}("progressToken" => "tok", "progress" => 1.0,
                                     "total" => 4.0, "message" => "go"),
    )
end

### Teardown ##################################################################

terminate()

end
