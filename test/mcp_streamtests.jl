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

# A raw `Channel` return value is adopted by the framework: values are
# normalized into progress events, and an exhausted channel ends the stream
# with empty content unless it carried a `result` marker.
@tool "Streams from a prefilled raw channel" Dict(:count => "number of steps") function stream_raw_channel(count::Int)
    channel = Channel{Any}(count)
    for i in 1:count
        put!(channel, "raw $i")
    end
    close(channel)
    return channel
end

@tool "Streams from a producer raw channel" Dict(:count => "number of steps") function stream_producer_channel(count::Int)
    return Channel{Any}(count) do channel
        for i in 1:count
            put!(channel, "produced $i")
        end
    end
end

# A raw channel may declare its final result with `result(value)`; earlier
# values are streamed as progress, and the marker ends the stream (the
# framework closes the channel) and becomes the tool result.
@tool "Completes a raw channel with a string result" Dict(:count => "number of steps") function stream_raw_result_text(count::Int)
    channel = Channel{Any}(count + 1)
    for i in 1:count
        put!(channel, "raw result step $i")
    end
    put!(channel, result("raw finished"))
    return channel
end

@tool "Completes a raw channel with a dict result" Dict(:count => "number of steps") function stream_raw_result_dict(count::Int)
    channel = Channel{Any}(count + 1)
    for i in 1:count
        put!(channel, "dict step $i")
    end
    put!(channel, result(Dict("count" => count, "ok" => true)))
    return channel
end

# The first marker ends the stream: the framework closes the channel, so
# anything written after it is never consumed.
@tool "Ends the stream at the first marker" Dict() function stream_raw_first_marker()
    channel = Channel{Any}(4)
    put!(channel, "before")
    put!(channel, result("first"))
    put!(channel, "after")
    put!(channel, result("second"))
    return channel
end

@tool "Fails inside a raw channel producer" Dict() function stream_raw_failure()
    return Channel{Any}(2) do channel
        put!(channel, "before the failure")
        error("raw producer boom")
    end
end

# A long raw-channel stream for the disconnect test; the payload is fat on
# purpose so the server's write fails shortly after the client hangs up.
const RAW_DISCONNECTED = Ref(0)

@tool "Long running raw channel stream" Dict() function stream_raw_long()
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
    # A call is quiet in two ways: the handler buffers a plain return value
    # (`stream_quiet`), or the handler has an injected `; stream` handle but the
    # request carried no progress token (`stream_quiet_injected`). Both must
    # answer a single JSON document.
    for (name, expected) in (("stream_quiet", "2"), ("stream_quiet_injected", "3"))
        payload = call_payload(name, Dict("value" => 1))
        response = json_call(payload; headers=call_headers(name))
        @test startswith(HTTP.header(response, "Content-Type"), "application/json")
        @test parsebody(response)["result"]["content"][1]["text"] == expected
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

@testset "raw channel handlers are adopted" begin
    # prefilled channel: every value becomes a progress event; a channel with
    # no `result` marker ends with empty content (never a fabricated "null"
    # block)
    response, frames = sse_call(call_payload("stream_raw_channel", Dict("count" => 2)))
    @test response.status == 200
    progress_frames = [frame for frame in frames if haskey(frame, "method") && frame["method"] == "notifications/progress"]
    @test [frame["params"]["message"] for frame in progress_frames] == ["raw 1", "raw 2"]
    result = only(filter(frame -> haskey(frame, "result"), frames))["result"]
    @test result["isError"] == false
    @test result["content"] == []

    # the drained (no token) path shapes the same empty content
    response = json_call(call_payload("stream_raw_channel", Dict("count" => 2); token=nothing);
                         headers=call_headers("stream_raw_channel"))
    @test parsebody(response)["result"]["content"] == []

    # producer channel: the framework drains the child task and closes the stream
    _, frames = sse_call(call_payload("stream_producer_channel", Dict("count" => 3)))
    progress_frames = [frame for frame in frames if haskey(frame, "method") && frame["method"] == "notifications/progress"]
    @test [frame["params"]["message"] for frame in progress_frames] == ["produced 1", "produced 2", "produced 3"]
    @test any(frame -> haskey(frame, "result"), frames)
end

@testset "result() builds the terminal marker" begin
    marker = MCP.result("done")
    @test marker isa MCP.FinalEvent
    @test marker.value == "done"
end

@testset "raw channel results match with and without streaming opted in" begin
    arguments = Dict("count" => 2)

    # opted in: progress notifications on the SSE stream, result as the last frame
    _, frames = sse_call(call_payload("stream_raw_result_text", arguments; id=41))
    progress_frames = [frame for frame in frames if haskey(frame, "method") && frame["method"] == "notifications/progress"]
    @test [frame["params"]["message"] for frame in progress_frames] ==
          ["raw result step 1", "raw result step 2"]
    streamed = only(filter(frame -> haskey(frame, "result"), frames))
    @test streamed["id"] == 41
    @test streamed["result"]["content"][1]["text"] == "raw finished"

    # not opted in: the drained path returns exactly the same JSON-RPC body
    response = json_call(call_payload("stream_raw_result_text", arguments; token=nothing, id=41);
                         headers=call_headers("stream_raw_result_text"))
    @test parsebody(response) == streamed
end

@testset "result() shapes strings and dicts for both spec eras" begin
    # modern: a dict result also carries structuredContent
    _, frames = sse_call(call_payload("stream_raw_result_dict", Dict("count" => 1)))
    final = frames[end]["result"]
    @test final["content"][1]["text"] == JSON.json(Dict("count" => 1, "ok" => true))
    @test final["structuredContent"] == Dict("count" => 1, "ok" => true)
    @test final["resultType"] == "complete"
    @test final["isError"] == false

    # legacy: structuredContent is kept (2025-11-25 emits it) but the modern
    # envelope (resultType / _meta) is not
    payload = call_payload("stream_raw_result_dict", Dict("count" => 1);
                           token="tok-legacy", modern=false, id=51)
    _, frames = sse_call(payload; headers=call_headers("stream_raw_result_dict"; modern=false))
    legacy = frames[end]["result"]
    @test !haskey(legacy, "resultType")
    @test !haskey(legacy, "_meta")
    @test legacy["structuredContent"] == Dict("count" => 1, "ok" => true)
    @test legacy["content"][1]["text"] == JSON.json(Dict("count" => 1, "ok" => true))
end

@testset "the first marker ends the stream" begin
    _, frames = sse_call(call_payload("stream_raw_first_marker", Dict()))
    progress_frames = [frame for frame in frames if haskey(frame, "method") && frame["method"] == "notifications/progress"]
    @test [frame["params"]["message"] for frame in progress_frames] == ["before"]
    final = only(filter(frame -> haskey(frame, "result"), frames))["result"]
    @test final["content"][1]["text"] == "first"
end

@testset "failing raw channel producers surface the real error" begin
    # opted in: the streamed value is followed by the error result
    payload = call_payload("stream_raw_failure", Dict())
    _, frames = sse_call(payload)
    progress_frames = [frame for frame in frames if haskey(frame, "method") && frame["method"] == "notifications/progress"]
    @test [frame["params"]["message"] for frame in progress_frames] == ["before the failure"]
    result = only(filter(frame -> haskey(frame, "result"), frames))["result"]
    @test result["isError"] == true
    @test result["content"][1]["text"] == "raw producer boom"

    # drained path: the same error result in one JSON body
    response = json_call(call_payload("stream_raw_failure", Dict(); token=nothing);
                         headers=call_headers("stream_raw_failure"))
    result = parsebody(response)["result"]
    @test result["isError"] == true
    @test result["content"][1]["text"] == "raw producer boom"
end

@testset "disconnect releases a raw channel producer" begin
    before = RAW_DISCONNECTED[]
    payload = call_payload("stream_raw_long", Dict(); id=61)
    io = HTTP.open("POST", STREAM_URL, call_headers("stream_raw_long"))
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
    while time() < deadline && RAW_DISCONNECTED[] == before
        sleep(0.1)
    end
    @test RAW_DISCONNECTED[] > before
end

@testset "content events have no default wire mapping" begin
    stream = MCP.MCPStream()
    event = MCP.ContentEvent(Dict{String,Any}("type" => "text", "text" => "x"))
    @test MCP.normalize_event(stream, event) === event
    @test MCP.serialize_event("tok", event) === nothing
end

@testset "a drain without a terminal event becomes an error result" begin
    call = MCP.StreamedCall(MCP.MCPStream(), 7, MCP.LATEST_LEGACY_SPEC)
    body = MCP.streamed_body(CONTEXT[], call, nothing)
    @test body["id"] == 7
    @test body["result"]["isError"] == true
    @test occursin("without a result", body["result"]["content"][1]["text"])
end

@testset "a stream cancelled before its first event answers nothing" begin
    # The producer was cancelled before its first emit (the client is gone), so
    # the channel is closed and empty; taking from it raises and the transport
    # unwinds without writing a partial response.
    stream = MCP.MCPStream()
    stream.protocol.token = "tok"
    close(stream.channel)

    ctx = Oxygen.Core.ServerContext()
    req = HTTP.Request("POST", "/mcp", ["Accept" => "text/event-stream"])
    @test MCP.accepts_event_stream(req)
    accepted = HTTP.Stream(req)
    call = MCP.StreamedCall(stream, 1, MCP.LATEST_LEGACY_SPEC)
    @test MCP.stream_call(ctx, accepted, req, call) === nothing
end

### Teardown ##################################################################

terminate()

end
