module MCPSubscriptionTests

using Test
using HTTP
using JSON
using Oxygen; @oxidize
using ..Constants

const MCP = Oxygen.Core.MCP
const Core = Oxygen.Core
const META_ID = MCP.META_SUBSCRIPTION_ID
const SUB_URL = "$localhost/mcp"
const MCP_CLIENT = HTTP.Client()

### Fixtures ###################################################################

@resource "sub://alpha" "Alpha resource" function sub_alpha()
    return "alpha"
end

@resource "sub://beta" "Beta resource" function sub_beta()
    return "beta"
end

@prompt "Subscription prompt" function sub_prompt()
    return "hello"
end

# A tool that publishes a resource update from inside a streamed call: the
# notification must reach subscriptions, never the call's own progress stream.
@tool "Publishes an update for sub://alpha" Dict(:steps => "number of steps") function publish_update(steps::Int)
    return mcp_stream() do stream
        for i in 1:steps
            put!(stream, "step $i")
        end
        notify_resource_updated("sub://alpha")
        return "updated"
    end
end

### Request helpers ############################################################

function req_meta()
    return Dict{String,Any}(
        "io.modelcontextprotocol/protocolVersion" => MCP.PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientInfo" => Dict{String,Any}("name" => "OxygenTests", "version" => "1.0.0"),
        "io.modelcontextprotocol/clientCapabilities" => Dict{String,Any}(),
    )
end

function raw_post(payload; headers=Pair{String,String}[])::HTTP.Response
    base = Pair{String,String}["Content-Type" => "application/json"]
    append!(base, headers)
    return HTTP.request("POST", SUB_URL, base, JSON.json(payload);
                        status_exception=false, client=MCP_CLIENT)
end

parsebody(r::HTTP.Response) = JSON.parse(String(copy(r.body)))

function rpc(method::String, params::AbstractDict; id=1, accept=nothing, headers=Pair{String,String}[])
    base = Pair{String,String}["MCP-Protocol-Version" => MCP.PROTOCOL_VERSION, "Mcp-Method" => method]
    accept === nothing || push!(base, "Accept" => accept)
    append!(base, headers)
    payload = Dict{String,Any}("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params)
    return raw_post(payload; headers=base)
end

listen_params(notifications) = Dict{String,Any}("_meta" => req_meta(), "notifications" => notifications)

# Open a listen POST that stays alive; frames are parsed JSON objects pushed in
# arrival order. `io_ref[]` is the connection, closed by the test to disconnect.
function open_listen(notifications; id=1, accept="text/event-stream")
    payload = JSON.json(Dict{String,Any}(
        "jsonrpc" => "2.0", "id" => id, "method" => "subscriptions/listen",
        "params" => listen_params(notifications)))
    io_ref = Ref{Any}(nothing)
    events = Channel{Any}(128)
    task = @async begin
        try
            HTTP.open("POST", SUB_URL,
                      ["Content-Type" => "application/json", "Accept" => accept,
                       "MCP-Protocol-Version" => MCP.PROTOCOL_VERSION,
                       "Mcp-Method" => "subscriptions/listen"];
                      client=HTTP.Client()) do io
                io_ref[] = io
                write(io, payload)
                HTTP.closewrite(io)
                for line in eachline(io)
                    startswith(line, "data:") || continue
                    push!(events, JSON.parse(strip(line[6:end])))
                end
            end
        catch
            # The connection died or the response was an error; the channel
            # closing is the signal either way.
        finally
            close(events)
        end
    end
    deadline = time() + 10
    while time() < deadline && io_ref[] === nothing && isopen(events)
        sleep(0.01)
    end
    return io_ref, events, task
end

function open_legacy_sink(; headers=Pair{String,String}[])
    io_ref = Ref{Any}(nothing)
    priming = Ref(false)
    frames = Channel{Any}(128)
    task = @async begin
        try
            HTTP.open("GET", SUB_URL, vcat(["Accept" => "text/event-stream"], headers);
                      client=HTTP.Client()) do io
                io_ref[] = io
                for line in eachline(io)
                    startswith(line, ": connected") && (priming[] = true)
                    startswith(line, "data:") || continue
                    push!(frames, JSON.parse(strip(line[6:end])))
                end
            end
        catch
        finally
            close(frames)
        end
    end
    # The priming comment proves the server chose the SSE path (and therefore
    # registered the broker subscription before writing it).
    deadline = time() + 10
    while time() < deadline && !priming[] && isopen(frames)
        sleep(0.01)
    end
    return io_ref, frames, task
end

function take_frame(frames; timeout=10)
    deadline = time() + timeout
    while time() < deadline
        isready(frames) && return take!(frames)
        sleep(0.01)
    end
    error("timed out waiting for an SSE frame")
end

function no_frame(frames; wait=0.4)
    sleep(wait)
    return !isready(frames)
end

# The listen registry is a Set of records (ids are only unique per connection,
# so they cannot key it); this is the by-id view the tests assert on.
has_listen(ctx, id) = any(r -> MCP.listen_key(r.id) == MCP.listen_key(id), ctx.mcp.listens)

# Wait until the broker holds exactly `n` subscriptions, i.e. all transport
# teardowns have pruned. Necessary when two streams share an id, where
# `has_listen` cannot tell which one is still live.
function wait_subscribers(n; timeout=15)
    deadline = time() + timeout
    while time() < deadline && MCP.subscribers(MCP.broker(CONTEXT[])) != n
        sleep(0.05)
    end
    return MCP.subscribers(MCP.broker(CONTEXT[])) == n
end

# Disconnect a listen and nudge the server into writing, so the teardown does
# not have to wait out the keepalive interval.
function disconnect_listen(io_ref, id)
    close(io_ref[])
    notify_tools_changed()
    notify_prompts_changed()
    notify_resources_changed()
    notify_resource_updated("sub://alpha")
    deadline = time() + 15
    while time() < deadline && has_listen(CONTEXT[], id)
        sleep(0.05)
    end
    return !has_listen(CONTEXT[], id)
end

### Adapter-level helpers ######################################################

function fresh_ctx()
    ctx = Core.ServerContext()
    Core.register_resource!(ctx, "sub://alpha", "Alpha", () -> "alpha"; name="alpha")
    return ctx
end

function adapter_listen(ctx, id, notifications)
    payload = Dict{String,Any}("params" => listen_params(notifications))
    return MCP.dispatch(ctx, nothing, id, "subscriptions/listen", payload;
                        spec=MCP.V2026_07_28)
end

# Legacy session state is context-wide (single-session semantics), so tests that
# assert delivery counts reset it to simulate a fresh session.
function reset_legacy!()
    ctx = CONTEXT[]
    ctx.mcp.initialized[] = false
    ctx.mcp.handshake_complete[] = false
    lock(ctx.mcp.subscriptions_lock) do
        empty!(ctx.mcp.legacy_subscriptions)
    end
    return nothing
end

### stdio helpers ##############################################################

function start_stdio()
    input = Base.BufferStream()
    output = Base.BufferStream()
    task = @async MCP.stdio_loop(CONTEXT[]; input=input, output=output)
    lines = Channel{String}(128)
    reader = @async begin
        try
            for line in eachline(output)
                push!(lines, line)
            end
        catch
        finally
            close(lines)
        end
    end
    return task, input, output, lines, reader
end

function send(input, payload)
    write(input, JSON.json(payload) * "\n")
    flush(input)
    return nothing
end

function next_line(lines; timeout=10)
    deadline = time() + timeout
    while time() < deadline
        isready(lines) && return JSON.parse(take!(lines))
        sleep(0.01)
    end
    error("timed out waiting for a stdio line")
end

function stop_stdio(task, input, output)
    close(input)
    wait(task)
    close(output)
    return nothing
end

### Server #####################################################################

serve(port=PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing)

### Modern HTTP ################################################################

@testset "discover advertises subscription capabilities" begin
    r = rpc("server/discover", Dict("_meta" => req_meta()))
    @test r.status == 200
    capabilities = parsebody(r)["result"]["capabilities"]
    @test capabilities["tools"]["listChanged"] == true
    @test capabilities["prompts"]["listChanged"] == true
    @test capabilities["resources"]["subscribe"] == true
    @test capabilities["resources"]["listChanged"] == true
end

@testset "listen acknowledges first and filters per stream" begin
    io_a, events_a, task_a = open_listen(
        Dict("resourcesListChanged" => true); id=11)
    ack_a = take_frame(events_a)
    @test ack_a["method"] == "notifications/subscriptions/acknowledged"
    @test !haskey(ack_a, "id")
    @test ack_a["params"]["_meta"][META_ID] == 11
    @test ack_a["params"]["notifications"] == Dict{String,Any}("resourcesListChanged" => true)

    io_b, events_b, task_b = open_listen(
        Dict("resourceSubscriptions" => ["sub://alpha"]); id=12)
    ack_b = take_frame(events_b)
    @test ack_b["params"]["_meta"][META_ID] == 12
    @test ack_b["params"]["notifications"]["resourceSubscriptions"] == ["sub://alpha"]
    @test !haskey(ack_b["params"]["notifications"], "resourcesListChanged")

    # Only the requested type reaches each stream; the count reports deliveries.
    @test notify_tools_changed() == 0
    @test notify_prompts_changed() == 0
    @test notify_resources_changed() == 1
    frame_a = take_frame(events_a)
    @test frame_a["method"] == "notifications/resources/list_changed"
    @test frame_a["params"]["_meta"][META_ID] == 11
    @test no_frame(events_b)

    @test notify_resource_updated("sub://alpha") == 1
    frame_b = take_frame(events_b)
    @test frame_b["method"] == "notifications/resources/updated"
    @test frame_b["params"]["uri"] == "sub://alpha"
    @test frame_b["params"]["_meta"][META_ID] == 12
    @test no_frame(events_a)

    @test notify_resource_updated("sub://beta") == 0

    @test disconnect_listen(io_a, 11)
    @test disconnect_listen(io_b, 12)
    @test MCP.subscribers(MCP.broker(CONTEXT[])) == 0
end

@testset "the acknowledgement always precedes concurrent notifications" begin
    stop = Ref(false)
    hammer = @async while !stop[]
        notify_resources_changed()
        yield()
    end

    io_ref, events, _ = open_listen(Dict("resourcesListChanged" => true); id=13)
    first_frame = take_frame(events)
    @test first_frame["method"] == "notifications/subscriptions/acknowledged"

    # Whatever queued up behind the ack are notifications, never another ack.
    sleep(0.2)
    rest = Any[]
    while isready(events)
        push!(rest, take!(events))
    end
    @test all(frame -> frame["method"] == "notifications/resources/list_changed", rest)

    stop[] = true
    wait(hammer)
    @test disconnect_listen(io_ref, 13)
end

@testset "listen rejects malformed and invalid requests" begin
    # filter must be an object / fields well-typed / non-empty
    r = rpc("subscriptions/listen", Dict("_meta" => req_meta(), "notifications" => "nope"))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32602

    r = rpc("subscriptions/listen", Dict("_meta" => req_meta(),
              "notifications" => Dict("resourceSubscriptions" => "nope")))
    @test parsebody(r)["error"]["code"] == -32602

    r = rpc("subscriptions/listen", Dict("_meta" => req_meta(),
              "notifications" => Dict("toolsListChanged" => "yes")))
    @test parsebody(r)["error"]["code"] == -32602

    r = rpc("subscriptions/listen", Dict("_meta" => req_meta(),
              "notifications" => Dict()))
    @test parsebody(r)["error"]["code"] == -32602

    # over the per-filter URI limit
    uris = ["sub://x$i" for i in 1:(MCP.MAX_RESOURCE_SUBSCRIPTIONS + 1)]
    r = rpc("subscriptions/listen", Dict("_meta" => req_meta(),
              "notifications" => Dict("resourceSubscriptions" => uris)))
    @test parsebody(r)["error"]["code"] == -32602

    # a valid filter without the SSE Accept range is rejected
    r = rpc("subscriptions/listen", listen_params(Dict("toolsListChanged" => true)))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600
    @test occursin("Accept: text/event-stream", parsebody(r)["error"]["message"])

    # ids must be string/int and bounded
    r = rpc("subscriptions/listen", listen_params(Dict("toolsListChanged" => true)); id=1.5)
    @test parsebody(r)["error"]["code"] == -32600
    r = rpc("subscriptions/listen", listen_params(Dict("toolsListChanged" => true));
            id="x"^(MCP.MAX_SUBSCRIPTION_ID_LENGTH + 1))
    @test parsebody(r)["error"]["code"] == -32600

    # the modern request contract still applies to listen
    payload = Dict{String,Any}("jsonrpc" => "2.0", "id" => 1, "method" => "subscriptions/listen",
                               "params" => listen_params(Dict("toolsListChanged" => true)))
    r = raw_post(payload; headers=["MCP-Protocol-Version" => MCP.PROTOCOL_VERSION])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    r = raw_post(payload; headers=["MCP-Protocol-Version" => "1900-01-01",
                                   "Mcp-Method" => "subscriptions/listen"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # legacy-only methods are unknown in the modern era
    r = rpc("resources/subscribe", Dict("_meta" => req_meta(), "uri" => "sub://alpha"))
    @test r.status == 404
    @test parsebody(r)["error"]["code"] == -32601
    r = rpc("resources/unsubscribe", Dict("_meta" => req_meta(), "uri" => "sub://alpha"))
    @test r.status == 404
    @test parsebody(r)["error"]["code"] == -32601
end

@testset "listen ids are scoped to a connection" begin
    count_id(id) = count(r -> MCP.listen_key(r.id) == MCP.listen_key(id), CONTEXT[].mcp.listens)

    # JSON-RPC ids are unique per client, not per server: two connections (two
    # clients behind a dev server) reusing an id are two independent streams.
    io_a, events_a, _ = open_listen(Dict("toolsListChanged" => true); id=14)
    @test take_frame(events_a)["params"]["_meta"][META_ID] == 14
    io_b, events_b, _ = open_listen(Dict("toolsListChanged" => true); id=14)
    @test take_frame(events_b)["params"]["_meta"][META_ID] == 14
    @test count_id(14) == 2

    # both are live and independently tagged
    @test notify_tools_changed() == 2
    @test take_frame(events_a)["params"]["_meta"][META_ID] == 14
    @test take_frame(events_b)["params"]["_meta"][META_ID] == 14

    # one client's disconnect must never prune the other's stream
    close(io_a[])
    notify_tools_changed()  # nudge the failed write that tears io_a down
    @test wait_subscribers(1)
    @test count_id(14) == 1
    @test take_frame(events_b)["method"] == "notifications/tools/list_changed"

    close(io_b[])
    notify_tools_changed()
    @test wait_subscribers(0)
    @test !has_listen(CONTEXT[], 14)
end

@testset "disconnect prunes the listen record" begin
    io_ref, events, _ = open_listen(Dict("resourcesListChanged" => true); id=15)
    take_frame(events)
    @test has_listen(CONTEXT[], 15)

    close(io_ref[])
    notify_resources_changed()  # force the failed write that tears the stream down

    deadline = time() + 15
    while time() < deadline && has_listen(CONTEXT[], 15)
        sleep(0.05)
    end
    @test !has_listen(CONTEXT[], 15)
    @test MCP.subscribers(MCP.broker(CONTEXT[])) == 0
end

### Adapter-level limits and lifecycle #########################################

@testset "honored subset masks undeliverable types" begin
    ctx = Core.ServerContext()
    Core.register_tool!(ctx, "only tool", Dict(), () -> "t"; name="only_tool")

    call, status = adapter_listen(ctx, 1, Dict(
        "toolsListChanged" => true,
        "promptsListChanged" => true,
        "resourcesListChanged" => true,
        "resourceSubscriptions" => ["sub://alpha"]))
    @test status == 200
    ack = take!(call.stream.channel)
    @test ack.params["notifications"] == Dict{String,Any}("toolsListChanged" => true)
    MCP.close_listens!(ctx)
end

@testset "listen capacity is enforced" begin
    ctx = fresh_ctx()
    calls = Any[]
    for id in 1:MCP.MAX_LISTEN_SUBSCRIPTIONS
        call, status = adapter_listen(ctx, id, Dict("resourcesListChanged" => true))
        @test status == 200
        push!(calls, call)
    end

    body, status = adapter_listen(ctx, 10_000, Dict("resourcesListChanged" => true))
    @test status == 400
    @test body["error"]["code"] == -32603

    # sweeping dead streams frees capacity
    close(calls[1].stream.channel)
    call, status = adapter_listen(ctx, 10_001, Dict("resourcesListChanged" => true))
    @test status == 200
    MCP.close_listens!(ctx)
    @test MCP.subscribers(MCP.broker(ctx)) == 0
end

@testset "listen backlog sheds on overflow and drains buffered frames" begin
    ctx = fresh_ctx()
    call, status = adapter_listen(ctx, 21, Dict("resourcesListChanged" => true))
    @test status == 200
    take!(call.stream.channel)  # ack

    for _ in 1:MCP.LISTEN_BACKLOG_CAP
        @test MCP.notify_resources_changed(ctx) == 1
    end

    # The queue is full: the next broadcast disconnects and prunes the stream.
    @test MCP.notify_resources_changed(ctx) == 0
    @test !isopen(call.stream.channel)
    @test Base.n_avail(call.stream.channel) == MCP.LISTEN_BACKLOG_CAP
    @test MCP.subscribers(MCP.broker(ctx)) == 0

    # Already-buffered frames stay drainable.
    while isready(call.stream.channel)
        take!(call.stream.channel)
    end
    MCP.close_listens!(ctx)
end

@testset "graceful shutdown closes listens with a complete result" begin
    ctx = fresh_ctx()
    call, status = adapter_listen(ctx, 31, Dict("resourcesListChanged" => true))
    @test status == 200
    take!(call.stream.channel)  # ack

    MCP.close_listens!(ctx)
    final = take!(call.stream.channel)
    @test final isa Core.Streaming.FinalEvent
    body = final.value
    @test body["id"] == 31
    @test body["result"]["resultType"] == "complete"
    @test body["result"]["_meta"][META_ID] == 31
    @test haskey(body["result"]["_meta"], "io.modelcontextprotocol/serverInfo")
    @test !isopen(call.stream.channel)

    # Nothing is delivered after the closing result.
    @test MCP.notify_resources_changed(ctx) == 0
    @test !isready(call.stream.channel)
    @test isempty(ctx.mcp.listens)
end

@testset "parse_subscription_filter rules" begin
    filter = MCP.parse_subscription_filter(Dict("unknownKey" => 1, "toolsListChanged" => true))
    @test filter isa MCP.SubscriptionFilter
    @test filter.tools_list_changed

    @test MCP.parse_subscription_filter(nothing) isa String
    @test MCP.parse_subscription_filter(Dict()) isa String
    @test MCP.parse_subscription_filter(Dict("resourceSubscriptions" => [1])) isa String
    @test MCP.parse_subscription_filter(Dict("resourceSubscriptions" => ["a", "b"])).resource_uris ==
          Set(["a", "b"])

    wire = MCP.filter_to_wire(filter)
    @test wire == Dict{String,Any}("toolsListChanged" => true)
end

### Legacy #####################################################################

@testset "legacy resource subscriptions over HTTP" begin
    reset_legacy!()
    init = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                "params" => Dict("protocolVersion" => "2025-11-25", "capabilities" => Dict(),
                                 "clientInfo" => Dict("name" => "legacy", "version" => "1.0")))
    @test parsebody(raw_post(init))["result"]["protocolVersion"] == "2025-11-25"
    raw_post(Dict("jsonrpc" => "2.0", "method" => "notifications/initialized"))

    subscribe = Dict("jsonrpc" => "2.0", "id" => 2, "method" => "resources/subscribe",
                     "params" => Dict("uri" => "sub://alpha"))
    @test parsebody(raw_post(subscribe))["result"] == Dict{String,Any}()

    io_ref, frames, _ = open_legacy_sink()
    @test io_ref[] !== nothing

    # subscribed URI updates arrive as a plain notification
    @test notify_resource_updated("sub://alpha") == 1
    update = take_frame(frames)
    @test update["method"] == "notifications/resources/updated"
    @test update["params"] == Dict{String,Any}("uri" => "sub://alpha")

    # other URIs and unadvertised kinds do not
    @test notify_resource_updated("sub://beta") == 0

    # list changes are capability-gated and delivered globally
    @test notify_resources_changed() == 1
    @test take_frame(frames)["method"] == "notifications/resources/list_changed"

    # unsubscribe stops delivery (idempotent)
    unsubscribe = Dict("jsonrpc" => "2.0", "id" => 3, "method" => "resources/unsubscribe",
                       "params" => Dict("uri" => "sub://alpha"))
    @test parsebody(raw_post(unsubscribe))["result"] == Dict{String,Any}()
    @test notify_resource_updated("sub://alpha") == 0
    @test no_frame(frames)

    # Close the sink and wait until its broker subscription is gone so later
    # delivery-count assertions are not raced by this connection.
    close(io_ref[])
    notify_resources_changed()
    broker = MCP.broker(CONTEXT[])
    deadline = time() + 15
    while time() < deadline && MCP.subscribers(broker) > 0
        sleep(0.05)
    end
    @test MCP.subscribers(broker) == 0
end

@testset "legacy sessions isolate subscriptions" begin
    ctx = CONTEXT[]
    session_init(version) = raw_post(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                                          "params" => Dict("protocolVersion" => version, "capabilities" => Dict())))
    subscribe(sid, uri, id) = raw_post(
        Dict("jsonrpc" => "2.0", "id" => id, "method" => "resources/subscribe",
             "params" => Dict("uri" => uri));
        headers=Pair{String,String}["Mcp-Session-Id" => sid])

    sid1 = HTTP.header(session_init("2025-11-25"), MCP.SESSION_HEADER)
    sid2 = HTTP.header(session_init("2025-11-25"), MCP.SESSION_HEADER)
    @test sid1 isa String && sid2 isa String && sid1 != sid2

    for sid in (sid1, sid2)
        raw_post(Dict("jsonrpc" => "2.0", "method" => "notifications/initialized");
                 headers=Pair{String,String}["Mcp-Session-Id" => sid])
    end

    @test parsebody(subscribe(sid1, "sub://alpha", 2))["result"] == Dict{String,Any}()
    @test parsebody(subscribe(sid2, "sub://beta", 3))["result"] == Dict{String,Any}()

    io1, frames1, _ = open_legacy_sink(headers=Pair{String,String}["Mcp-Session-Id" => sid1])
    io2, frames2, _ = open_legacy_sink(headers=Pair{String,String}["Mcp-Session-Id" => sid2])
    @test io1[] !== nothing && io2[] !== nothing

    # each sink only sees the update its own session subscribed to
    @test notify_resource_updated("sub://alpha") == 1
    @test take_frame(frames1)["params"]["uri"] == "sub://alpha"
    @test no_frame(frames2)

    @test notify_resource_updated("sub://beta") == 1
    @test take_frame(frames2)["params"]["uri"] == "sub://beta"
    @test no_frame(frames1)

    # DELETE terminates the session and its notification stream
    r = HTTP.request("DELETE", SUB_URL, ["Mcp-Session-Id" => sid1];
                     status_exception=false, client=MCP_CLIENT)
    @test r.status == 200
    @test !haskey(ctx.mcp.sessions, sid1)
    deadline = time() + 10
    while time() < deadline && MCP.subscribers(MCP.broker(ctx)) > 1
        sleep(0.05)
    end
    @test MCP.subscribers(MCP.broker(ctx)) == 1   # the other session's sink only
    @test notify_resource_updated("sub://alpha") == 0

    # a request naming the terminated session is rejected
    r = raw_post(Dict("jsonrpc" => "2.0", "id" => 5, "method" => "ping", "params" => Dict());
                 headers=Pair{String,String}["Mcp-Session-Id" => sid1])
    @test r.status == 404

    # clean up the remaining sink
    close(io2[])
    notify_resource_updated("sub://beta")
    deadline = time() + 10
    while time() < deadline && MCP.subscribers(MCP.broker(ctx)) > 0
        sleep(0.05)
    end
    @test MCP.subscribers(MCP.broker(ctx)) == 0
end

@testset "legacy delivery requires a completed handshake" begin
    ctx = fresh_ctx()
    sub = MCP.subscribe_legacy!(ctx)
    lock(ctx.mcp.subscriptions_lock) do
        push!(ctx.mcp.legacy_subscriptions, "sub://alpha")
    end

    @test MCP.notify_resource_updated(ctx, "sub://alpha") == 0   # nothing initialized
    ctx.mcp.initialized[] = true
    @test MCP.notify_resource_updated(ctx, "sub://alpha") == 0   # initialized without a handshake
    ctx.mcp.handshake_complete[] = true
    @test MCP.notify_resource_updated(ctx, "sub://alpha") == 1
    @test take!(sub.queue).method == "notifications/resources/updated"
    @test !isready(sub.queue)
end

@testset "legacy list_changed is capability-gated" begin
    ctx = Core.ServerContext()
    Core.register_tool!(ctx, "gate tool", Dict(), () -> "t"; name="gate_tool")
    sub = MCP.subscribe_legacy!(ctx)
    ctx.mcp.initialized[] = true
    ctx.mcp.handshake_complete[] = true

    @test MCP.notify_prompts_changed(ctx) == 0    # no prompts capability
    @test MCP.notify_resources_changed(ctx) == 0  # no resources capability
    @test MCP.notify_tools_changed(ctx) == 1      # tools are always advertised
    @test take!(sub.queue).method == "notifications/tools/list_changed"
end

@testset "legacy resources/subscribe needs a URI" begin
    r = rpc("resources/subscribe", Dict("_meta" => req_meta()))
    @test r.status == 404  # modern era sees no such method

    ctx = Core.ServerContext()
    body, status = MCP.dispatch(ctx, nothing, 1, "resources/subscribe",
                                Dict("params" => Dict()); spec=MCP.LATEST_LEGACY_SPEC)
    @test status == 200
    @test body["error"]["code"] == -32602
end

### stdio ######################################################################

@testset "stdio listen: ack, tagged delivery, cancellation" begin
    reset_legacy!()
    task, input, output, lines, reader = start_stdio()

    send(input, Dict("jsonrpc" => "2.0", "id" => 5, "method" => "subscriptions/listen",
                     "params" => listen_params(Dict("resourceSubscriptions" => ["sub://alpha"]))))
    ack = next_line(lines)
    @test ack["method"] == "notifications/subscriptions/acknowledged"
    @test ack["params"]["_meta"][META_ID] == 5
    @test ack["params"]["notifications"]["resourceSubscriptions"] == ["sub://alpha"]

    @test notify_resource_updated("sub://alpha") == 1
    update = next_line(lines)
    @test update["method"] == "notifications/resources/updated"
    @test update["params"]["uri"] == "sub://alpha"
    @test update["params"]["_meta"][META_ID] == 5

    # unrequested types are never written
    @test notify_resources_changed() == 0

    # notifications/cancelled ends the stream without a response
    send(input, Dict("jsonrpc" => "2.0", "method" => "notifications/cancelled",
                     "params" => Dict("requestId" => 5)))
    deadline = time() + 5
    while time() < deadline && has_listen(CONTEXT[], 5)
        sleep(0.02)
    end
    @test !has_listen(CONTEXT[], 5)
    @test notify_resource_updated("sub://alpha") == 0

    stop_stdio(task, input, output)
end

@testset "stdio listen: duplicate ids are rejected" begin
    task, input, output, lines, reader = start_stdio()

    send(input, Dict("jsonrpc" => "2.0", "id" => 7, "method" => "subscriptions/listen",
                     "params" => listen_params(Dict("toolsListChanged" => true))))
    ack = next_line(lines)
    @test ack["method"] == "notifications/subscriptions/acknowledged"
    @test ack["params"]["_meta"][META_ID] == 7

    # one connection owns every stdio stream, so a reused id would make the
    # wire subscription id and `notifications/cancelled` ambiguous
    send(input, Dict("jsonrpc" => "2.0", "id" => 7, "method" => "subscriptions/listen",
                     "params" => listen_params(Dict("toolsListChanged" => true))))
    body = next_line(lines)
    @test body["id"] == 7
    @test body["error"]["code"] == -32600
    @test occursin("already active", body["error"]["message"])

    stop_stdio(task, input, output)
end

@testset "stdio listen: EOF closes streams gracefully" begin
    task, input, output, lines, reader = start_stdio()

    send(input, Dict("jsonrpc" => "2.0", "id" => 6, "method" => "subscriptions/listen",
                     "params" => listen_params(Dict("toolsListChanged" => true))))
    ack = next_line(lines)
    @test ack["method"] == "notifications/subscriptions/acknowledged"
    @test ack["params"]["_meta"][META_ID] == 6

    close(input)
    final = next_line(lines)
    @test final["id"] == 6
    @test final["result"]["resultType"] == "complete"
    @test final["result"]["_meta"][META_ID] == 6
    wait(task)
    @test isempty(CONTEXT[].mcp.listens)
    close(output)
end

@testset "stdio legacy delivery interleaves as whole lines" begin
    reset_legacy!()
    task, input, output, lines, reader = start_stdio()

    send(input, Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                     "params" => Dict("protocolVersion" => "2025-11-25",
                                      "capabilities" => Dict(),
                                      "clientInfo" => Dict("name" => "legacy", "version" => "1.0"))))
    @test next_line(lines)["result"]["protocolVersion"] == "2025-11-25"
    send(input, Dict("jsonrpc" => "2.0", "method" => "notifications/initialized"))
    send(input, Dict("jsonrpc" => "2.0", "id" => 2, "method" => "resources/subscribe",
                     "params" => Dict("uri" => "sub://alpha")))
    @test next_line(lines)["id"] == 2

    # the update is plain: no subscription tagging on the legacy channel
    @test notify_resource_updated("sub://alpha") == 1
    update = next_line(lines)
    @test update["method"] == "notifications/resources/updated"
    @test update["params"] == Dict{String,Any}("uri" => "sub://alpha")

    # an ordinary request still comes back as its own line
    send(input, Dict("jsonrpc" => "2.0", "id" => 3, "method" => "tools/list", "params" => Dict()))
    list = next_line(lines)
    @test list["id"] == 3
    @test any(t -> t["name"] == "publish_update", list["result"]["tools"])

    stop_stdio(task, input, output)
end

@testset "stdio notifier serializes concurrent writes line-atomically" begin
    output = IOBuffer()
    notifier = MCP.StdioNotifier(output)
    @sync for i in 1:100
        @async MCP.respond(notifier, Dict("i" => i))
    end

    lines = split(strip(String(take!(output))), "\n")
    @test length(lines) == 100
    @test sort([JSON.parse(line)["i"] for line in lines]) == collect(1:100)
end

@testset "stdio notifier prunes finished forwarding tasks" begin
    ctx = fresh_ctx()
    notifier = MCP.StdioNotifier(IOBuffer())

    for id in 1:5
        call, status = adapter_listen(ctx, id, Dict("toolsListChanged" => true))
        @test status == 200
        MCP.forward_listen_call(ctx, notifier, call)
        MCP.close_listens!(ctx)
        deadline = time() + 5
        while time() < deadline && !all(istaskdone, notifier.tasks)
            sleep(0.01)
        end
    end

    # Finished tasks are dropped on the next push, so a long-lived notifier
    # holds at most the live task instead of one per closed stream.
    @test length(notifier.tasks) <= 1
    MCP.close_notifier!(notifier)
end

### Regression / lifecycle #####################################################

@testset "a notify inside a tool handler never lands on its progress stream" begin
    payload = Dict{String,Any}("jsonrpc" => "2.0", "id" => 41, "method" => "tools/call",
                               "params" => Dict{String,Any}(
                                   "name" => "publish_update",
                                   "arguments" => Dict("steps" => 2),
                                   "_meta" => merge(req_meta(), Dict("progressToken" => "tok-1"))))
    frames = Any[]
    HTTP.open("POST", SUB_URL, ["Content-Type" => "application/json",
                                "Accept" => "application/json, text/event-stream",
                                "MCP-Protocol-Version" => MCP.PROTOCOL_VERSION,
                                "Mcp-Method" => "tools/call",
                                "Mcp-Name" => "publish_update"];
               client=HTTP.Client()) do io
        write(io, JSON.json(payload))
        HTTP.closewrite(io)
        for line in eachline(io)
            startswith(line, "data:") || continue
            push!(frames, JSON.parse(strip(line[6:end])))
        end
    end

    @test length(frames) == 3
    @test all(frame -> frame["method"] == "notifications/progress", frames[1:2])
    @test frames[end]["result"]["content"][1]["text"] == "updated"
    @test !any(frame -> haskey(frame, "method") &&
                         frame["method"] == "notifications/resources/updated", frames)
end

@testset "a tool handler update reaches an open listen stream" begin
    io_ref, events, _ = open_listen(Dict("resourceSubscriptions" => ["sub://alpha"]); id=51)
    take_frame(events)  # ack

    # Mutate through a tool (the path the demo's add_place uses); its
    # notify_resource_updated must reach the subscription created above.
    payload = Dict{String,Any}("jsonrpc" => "2.0", "id" => 52, "method" => "tools/call",
                               "params" => Dict{String,Any}(
                                   "name" => "publish_update",
                                   "arguments" => Dict("steps" => 1),
                                   "_meta" => req_meta()))
    response = raw_post(payload; headers=Pair{String,String}[
        "MCP-Protocol-Version" => MCP.PROTOCOL_VERSION,
        "Mcp-Method" => "tools/call",
        "Mcp-Name" => "publish_update"])
    @test response.status == 200
    @test parsebody(response)["result"]["content"][1]["text"] == "updated"

    frame = take_frame(events)
    @test frame["method"] == "notifications/resources/updated"
    @test frame["params"]["uri"] == "sub://alpha"
    @test frame["params"]["_meta"][META_ID] == 51

    @test disconnect_listen(io_ref, 51)
end

@testset "instance subscriptions are isolated" begin
    app = Oxygen.instance()
    app.resource("iso://sub", "Instance resource", () -> "iso"; name="iso_sub")
    iso_ctx = app.custom_module.CONTEXT[]

    @test iso_ctx.mcp.broker[] !== nothing
    @test CONTEXT[].mcp.broker[] !== iso_ctx.mcp.broker[]
    @test isempty(iso_ctx.mcp.listens)
end

### Teardown ###################################################################

terminate()

@testset "resetstate clears subscription state" begin
    # `resetstate` only resets the module-global context (the `@__MODULE__`
    # guard in methods.jl), so seed subscription state in Oxygen's context and
    # verify the whole context — broker included — is replaced.
    ctx = Oxygen.CONTEXT[]
    MCP.broker(ctx)
    lock(ctx.mcp.subscriptions_lock) do
        push!(ctx.mcp.legacy_subscriptions, "sub://alpha")
    end
    @test ctx.mcp.broker[] !== nothing
    @test !isempty(ctx.mcp.legacy_subscriptions)

    Oxygen.resetstate()

    @test Oxygen.CONTEXT[] !== ctx
    @test Oxygen.CONTEXT[].mcp.broker[] === nothing
    @test isempty(Oxygen.CONTEXT[].mcp.listens)
    @test isempty(Oxygen.CONTEXT[].mcp.legacy_subscriptions)
end

end
