module MCPStreamingDemo

using Oxygen
using HTTP
using JSON

# Port 8080 is the demo default elsewhere, but it is commonly taken by local
# dev servers; the streaming demo binds nearby.
const PORT = 8081
const URL = "http://127.0.0.1:$PORT/mcp"
const VERSION = "2026-07-28"

### Tools #####################################################################

# The non-streaming probe: this handler does not opt into streaming, so a
# `tools/call` with a progressToken still answers with one JSON body after all
# the work is done. This is the behavior streaming changes only for handlers
# that ask for it.
@tool "Count steps without streaming" Dict(:count => "how many 0.4s steps") function count_slow(count::Int)
    for _ in 1:count
        sleep(0.4)
    end
    return "counted $count steps"
end

# Streaming form 1 — explicit progress: the handler controls the value and can
# send a `total` and a message via `progress(i, total; message=...)`. The
# do-block's return value is the final `CallToolResult`.
@tool "Import a catalog" Dict(:urls => "catalog URLs") function import_catalog(urls::Vector{String})
    return mcp_stream() do stream
        total = length(urls)
        for (i, url) in enumerate(urls)
            sleep(0.4)  # stand-in for real work
            put!(stream, progress(i, total; message="imported $url"))
        end
        return "Imported $total records"
    end
end

# Streaming form 2 — auto-numbered yields: a plain string is classified by the
# framework into a progress notification with the auto-incremented counter and
# the string as its message, so there is no counter to track in user code.
# Yields may also be `nothing` (heartbeat), a `Real` (explicit value), or any
# other value (JSON-encoded into the message).
@tool "Sync files" Dict(:files => "file names") function sync_files(files::Vector{String})
    return mcp_stream() do stream
        for file in files
            sleep(0.4)
            put!(stream, "synced $file")  # auto progress 1, 2, 3, ...
        end
        return "Synced $(length(files)) files"
    end
end

### Probes ####################################################################

function payload(payload_id::Int, name::String, arguments; token="tok-$(payload_id)")
    meta = Dict{String,Any}(
        "io.modelcontextprotocol/protocolVersion" => VERSION,
        "io.modelcontextprotocol/clientCapabilities" => Dict{String,Any}(),
        "progressToken" => token,
    )
    return Dict{String,Any}(
        "jsonrpc" => "2.0", "id" => payload_id, "method" => "tools/call",
        "params" => Dict{String,Any}("_meta" => meta, "name" => name, "arguments" => arguments),
    )
end

function headers(name::String; accept="application/json, text/event-stream")
    return [
        "Content-Type" => "application/json",
        "Accept" => accept,
        "MCP-Protocol-Version" => VERSION,
        "Mcp-Method" => "tools/call",
        "Mcp-Name" => name,
    ]
end

# Call a tool and consume the SSE `data:` frames as they arrive, printing each
# with its elapsed time. Returns the elapsed time of the first progress frame
# and of the final result frame.
function probe_stream(name::String, arguments)
    println("=== streaming tools/call: $name ===")
    start = time()
    progress_times = Float64[]
    result_time = Ref(0.0)

    HTTP.open("POST", URL, headers(name)) do io
        write(io, JSON.json(payload(1, name, arguments)))
        HTTP.closewrite(io)
        for line in eachline(io)
            startswith(line, "data:") || continue
            message = JSON.parse(strip(line[6:end]))
            elapsed = round(time() - start; digits=2)
            if get(message, "method", "") == "notifications/progress"
                push!(progress_times, elapsed)
                params = message["params"]
                total = get(params, "total", nothing)
                steps = total === nothing ? " (auto)" : " / $(Int(total))"
                println("+$(elapsed)s  notifications/progress  $(params["progress"])$steps  $(get(params, "message", ""))")
            elseif haskey(message, "result")
                result_time[] = elapsed
                println("+$(elapsed)s  final result: $(message["result"]["content"][1]["text"])")
            end
        end
    end

    @assert !isempty(progress_times) "no progress frame arrived"
    @assert all(t -> t <= result_time[], progress_times) "a progress frame arrived after the final result"
    @assert first(progress_times) <= result_time[] - 0.3 "progress frames did not arrive while the tool was still running"
    println("PASS: progress frames arrived before the final result")
    println()
    return first(progress_times), result_time[]
end

# The buffered probe: no SSE, one JSON body at the end.
function probe_json(name::String, arguments)
    println("=== non-streaming tools/call: $name ===")
    start = time()
    response = HTTP.request("POST", URL, headers(name; accept="application/json"),
                            JSON.json(payload(2, name, arguments)); status_exception=false)
    elapsed = round(time() - start; digits=2)
    println("+$(elapsed)s  status $(response.status)  $(HTTP.header(response, "Content-Type"))")
    body = JSON.parse(String(response.body))
    @assert response.status == 200
    @assert HTTP.header(response, "Content-Type") == "application/json; charset=utf-8"
    @assert body["result"]["content"][1]["text"] == "counted 3 steps"
    println("PASS: non-streaming call stayed plain JSON")
    println()
    return elapsed
end

serve(port=PORT, host="127.0.0.1", async=true, show_banner=false, show_errors=false, access_log=nothing)
sleep(0.5)

probe_json("count_slow", Dict("count" => 3))
probe_stream("import_catalog", Dict("urls" => ["a.json", "b.json", "c.json"]))
probe_stream("sync_files", Dict("files" => ["one.txt", "two.txt", "three.txt"]))

terminate()

end
