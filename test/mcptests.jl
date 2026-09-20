module MCPTests

using Test
using HTTP
using JSON
using Base64
using Oxygen; @oxidize
using ..Constants

const MCP = Oxygen.Core.MCP

### Test types ####

@kwdef struct Coordinates
    lat::Float64
    lon::Float64
end

@kwdef struct Place
    name::String
    coordinates::Coordinates
    tags::Vector{String} = String[]
end

@enum Color red = 1 blue = 2 green = 3

### Registered tools ###

@tool "Add two integers" Dict(:a => "first number", :b => "second number") function add_numbers(a::Int, b::Int)
    return a + b
end

@tool "Concatenate two strings" Dict(:a => "left", :b => "right") function concatenate(a::String, b::String)
    return a * b
end

@tool "Has a default" Dict(:x => "required", :y => "optional") function with_default(x::Int, y::Int=10)
    return x + y
end

@tool "Takes no arguments" Dict() function no_args()
    return Dict("ok" => true)
end

@tool "Takes an enum" Dict(:color => "a color") function enum_tool(color::Color)
    return Int(color)
end

@tool "Takes a struct" Dict(:place => "a place") function struct_tool(place::Place)
    return place.name
end

@tool "Takes a vector" Dict(:nums => "numbers") function vector_tool(nums::Vector{Int})
    return sum(nums)
end

@tool "Always throws" Dict() function throws_tool()
    error("boom")
end

@tool "Returns a value that cannot be serialized" Dict() function unserializable_tool()
    return NaN
end

@tool "Reads the injected context" Dict() function context_tool(; context)
    return context isa Missing ? "missing" : context.label
end

@tool "Reads the injected request" Dict() function request_tool(; request)
    return string(request.method)
end

@tool "Block form tool" Dict(:value => "a value") begin
    function block_tool(value::Int)
        return value + 1
    end
end

@tool "Returns an HTTP.Response" Dict() function response_tool()
    return text("plain response")
end

@tool "Struct returning tool" Dict(:place => "a place") function echo_place(place::Place)
    return place
end

# function + tool form
function subtract(a::Int, b::Int)
    return a - b
end
tool("Subtract two integers", Dict(:a => "left", :b => "right"), subtract)

# do..block form with an explicit wire name
tool("Multiply two integers", Dict(:x => "left", :y => "right"); name="multiply") do x::Int, y::Int
    return x * y
end

### Request helpers ###########################################################

struct AppState
    label::String
end

# A dedicated client keeps MCP test requests off the global connection pool,
# which may hold keep-alive sockets for other test servers bound to the same port.
const MCP_CLIENT = HTTP.Client()

function raw_post(payload; headers=[])::HTTP.Response
    h = ["Content-Type" => "application/json"]
    append!(h, headers)
    return HTTP.request("POST", "$localhost/mcp", h, JSON.json(payload);
                        status_exception=false, client=MCP_CLIENT)
end

function req_meta()
    return Dict(
        "io.modelcontextprotocol/protocolVersion" => MCP.PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientInfo" => Dict("name" => "OxygenTests", "version" => "1.0.0"),
        "io.modelcontextprotocol/clientCapabilities" => Dict(),
    )
end

function rpc(method::String, params::AbstractDict; extra_headers=[], id=1)::HTTP.Response
    headers = ["MCP-Protocol-Version" => MCP.PROTOCOL_VERSION, "Mcp-Method" => method]
    append!(headers, extra_headers)
    payload = Dict("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params)
    return raw_post(payload; headers=headers)
end

function call_tool(name::String, arguments::AbstractDict; extra_headers=[])::HTTP.Response
    params = Dict("_meta" => req_meta(), "name" => name, "arguments" => arguments)
    return rpc("tools/call", params; extra_headers=vcat(["Mcp-Name" => name], extra_headers))
end

parsebody(r::HTTP.Response) = JSON.parse(String(r.body))

serve(port=PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing, context=AppState("injected"))

### Tests #####################################################################

@testset "tool registry" begin
    tools = CONTEXT[].mcp.tools
    for name in ["add_numbers", "concatenate", "with_default", "no_args", "enum_tool",
                 "struct_tool", "vector_tool", "throws_tool", "context_tool",
                 "request_tool", "block_tool", "response_tool", "echo_place",
                 "subtract", "multiply"]
        @test haskey(tools, name)
    end

    # macros and tool are the only write paths; nothing leaked into the global context
    @test !haskey(Oxygen.CONTEXT[].mcp.tools, "add_numbers")
end

@testset "reflection" begin
    tool = CONTEXT[].mcp.tools["add_numbers"]
    @test tool.has_context == false
    @test tool.has_request == false
    @test tool.argnames == [:a, :b]

    a_param = tool.params[1]
    b_param = tool.params[2]
    @test a_param.param.type == Int
    @test a_param.description == "first number"
    @test Oxygen.Core.isrequired(a_param.param)
    @test Oxygen.Core.isrequired(b_param.param)

    default_tool_ = CONTEXT[].mcp.tools["with_default"]
    @test Oxygen.Core.isrequired(default_tool_.params[1].param)
    @test !Oxygen.Core.isrequired(default_tool_.params[2].param)
    @test default_tool_.params[2].param.default == 10

    ctx_tool = CONTEXT[].mcp.tools["context_tool"]
    @test ctx_tool.has_context == true
    @test isempty(ctx_tool.params)  # context is never part of the schema

    req_tool = CONTEXT[].mcp.tools["request_tool"]
    @test req_tool.has_request == true
    @test isempty(req_tool.params)  # request is never part of the schema
end

@testset "input schema" begin
    add = MCP.inputschema(CONTEXT[].mcp.tools["add_numbers"])
    @test add["type"] == "object"
    @test sort(add["required"]) == ["a", "b"]
    @test add["properties"]["a"]["type"] == "integer"
    @test add["properties"]["a"]["format"] == "int64"
    @test add["properties"]["a"]["description"] == "first number"

    default_schema = MCP.inputschema(CONTEXT[].mcp.tools["with_default"])
    @test default_schema["required"] == ["x"]
    @test default_schema["properties"]["y"]["default"] == 10

    empty_schema = MCP.inputschema(CONTEXT[].mcp.tools["no_args"])
    @test empty_schema["additionalProperties"] == false

    enum_schema = MCP.inputschema(CONTEXT[].mcp.tools["enum_tool"])
    @test enum_schema["properties"]["color"]["enum"] == [1, 2, 3]
    @test enum_schema["properties"]["color"]["type"] == "integer"

    vec_schema = MCP.inputschema(CONTEXT[].mcp.tools["vector_tool"])
    @test vec_schema["properties"]["nums"]["type"] == "array"
    @test vec_schema["properties"]["nums"]["items"]["type"] == "integer"

    struct_schema = MCP.inputschema(CONTEXT[].mcp.tools["struct_tool"])
    @test struct_schema["properties"]["place"]["\$ref"] == "#/\$defs/Place"
    @test haskey(struct_schema["\$defs"], "Place")
    @test haskey(struct_schema["\$defs"], "Coordinates")
    @test !occursin("#/components/schemas/", JSON.json(struct_schema))
end

@testset "parse_tool_argument" begin
    @test MCP.parse_tool_argument(Int, 3) === 3
    @test MCP.parse_tool_argument(Int, "3") === 3
    @test MCP.parse_tool_argument(Float64, 3) === 3.0
    @test MCP.parse_tool_argument(Bool, true) === true
    @test MCP.parse_tool_argument(Union{String, Nothing}, nothing) === nothing
    @test MCP.parse_tool_argument(String, 3) == "3"
    @test MCP.parse_tool_argument(Color, 2) == blue
    @test MCP.parse_tool_argument(Color, "3") == green
    @test MCP.parse_tool_argument(Coordinates, Dict("lat" => 1.0, "lon" => 2.0)) == Coordinates(1.0, 2.0)
    @test MCP.parse_tool_argument(Vector{Int}, [1, 2, 3]) == [1, 2, 3]
    @test MCP.parse_tool_argument(Vector{Int}, ["1", "2"]) == [1, 2]
    @test MCP.parse_tool_argument(Vector{Bool}, ["true", "false"]) == [true, false]
    @test MCP.parse_tool_argument(Vector{Union{Coordinates, Nothing}},
                                  [Dict("lat" => 1.0, "lon" => 2.0), nothing]) == [Coordinates(1.0, 2.0), nothing]
    @test MCP.parse_tool_argument(Vector{Union{Color, Nothing}}, [1, nothing]) == [red, nothing]
end

@testset "server/discover" begin
    r = rpc("server/discover", Dict("_meta" => req_meta()))
    @test r.status == 200
    body = parsebody(r)
    result = body["result"]
    @test result["resultType"] == "complete"
    @test result["supportedVersions"] == ["2026-07-28"]
    @test haskey(result["capabilities"], "tools")
    @test result["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "Oxygen"
    @test result["cacheScope"] == "public"
end

@testset "tools/list" begin
    r = rpc("tools/list", Dict("_meta" => req_meta()))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["cacheScope"] == "public"
    @test result["ttlMs"] isa Integer

    names = [tool["name"] for tool in result["tools"]]
    @test names == sort(names)
    @test "add_numbers" in names
    @test "multiply" in names

    add = only(filter(t -> t["name"] == "add_numbers", result["tools"]))
    @test add["description"] == "Add two integers"
    @test add["inputSchema"]["properties"]["a"]["type"] == "integer"
end

@testset "tools/call happy path" begin
    r = call_tool("add_numbers", Dict("a" => 2, "b" => 3))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["isError"] == false
    @test result["content"][1]["type"] == "text"
    @test result["content"][1]["text"] == "5"
    @test result["structuredContent"] == 5

    # strings are returned as text only
    r = call_tool("concatenate", Dict("a" => "ab", "b" => "cd"))
    result = parsebody(r)["result"]
    @test result["content"][1]["text"] == "abcd"

    # defaulted positional argument
    r = call_tool("with_default", Dict("x" => 5))
    @test parsebody(r)["result"]["structuredContent"] == 15

    # do..block registered tool
    r = call_tool("multiply", Dict("x" => 6, "y" => 7))
    @test parsebody(r)["result"]["structuredContent"] == 42

    # @tool block form
    r = call_tool("block_tool", Dict("value" => 1))
    @test parsebody(r)["result"]["structuredContent"] == 2

    # function + tool registered tool
    r = call_tool("subtract", Dict("a" => 10, "b" => 4))
    @test parsebody(r)["result"]["structuredContent"] == 6

    # enum argument
    r = call_tool("enum_tool", Dict("color" => 2))
    @test parsebody(r)["result"]["structuredContent"] == 2

    # vector argument
    r = call_tool("vector_tool", Dict("nums" => [1, 2, 3, 4]))
    @test parsebody(r)["result"]["structuredContent"] == 10

    # struct argument
    r = call_tool("struct_tool", Dict("place" => Dict(
        "name" => "NYC",
        "coordinates" => Dict("lat" => 40.7, "lon" => -74.0),
    )))
    @test parsebody(r)["result"]["content"][1]["text"] == "NYC"

    # struct return value mirrored into structuredContent
    r = call_tool("echo_place", Dict("place" => Dict(
        "name" => "LA",
        "coordinates" => Dict("lat" => 34.0, "lon" => -118.2),
        "tags" => ["west"],
    )))
    result = parsebody(r)["result"]
    @test result["structuredContent"]["name"] == "LA"
    @test result["structuredContent"]["tags"] == ["west"]

    # HTTP.Response return value
    r = call_tool("response_tool", Dict())
    @test parsebody(r)["result"]["content"][1]["text"] == "plain response"
end

@testset "tools/call errors" begin
    # missing required argument
    r = call_tool("add_numbers", Dict("a" => 1))
    @test r.status == 200
    @test parsebody(r)["error"]["code"] == -32602

    # unknown tool
    r = call_tool("does_not_exist", Dict())
    @test parsebody(r)["error"]["code"] == -32602

    # handler throws -> tool execution error
    r = call_tool("throws_tool", Dict())
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["isError"] == true
    @test occursin("boom", result["content"][1]["text"])

    # unserializable return value -> tool execution error, server stays up
    r = call_tool("unserializable_tool", Dict())
    @test r.status == 200
    @test parsebody(r)["result"]["isError"] == true

    r = call_tool("add_numbers", Dict("a" => 1, "b" => 1))
    @test parsebody(r)["result"]["structuredContent"] == 2
end

@testset "context injection" begin
    r = call_tool("context_tool", Dict())
    @test parsebody(r)["result"]["content"][1]["text"] == "injected"

    r = call_tool("request_tool", Dict())
    @test parsebody(r)["result"]["content"][1]["text"] == "POST"
end

@testset "header validation" begin
    payload = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => Dict("_meta" => req_meta()))

    # missing MCP-Protocol-Version header
    r = raw_post(payload; headers=["Mcp-Method" => "tools/list"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # protocol version header/body mismatch
    r = raw_post(payload; headers=["MCP-Protocol-Version" => "2025-06-18", "Mcp-Method" => "tools/list"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # missing Mcp-Method
    r = raw_post(payload; headers=["MCP-Protocol-Version" => "2026-07-28"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # Mcp-Method mismatch
    r = raw_post(payload; headers=["MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/call"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # Mcp-Name mismatch
    call_params = Dict("_meta" => req_meta(), "name" => "add_numbers", "arguments" => Dict("a" => 1, "b" => 1))
    r = rpc("tools/call", call_params; extra_headers=["Mcp-Name" => "concatenate"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # missing _meta.clientCapabilities
    bare_meta = Dict("io.modelcontextprotocol/protocolVersion" => "2026-07-28")
    r = rpc("tools/list", Dict("_meta" => bare_meta))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32602
end

@testset "protocol version" begin
    unsupported = "1900-01-01"
    payload = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list",
                   "params" => Dict("_meta" => Dict(
                       "io.modelcontextprotocol/protocolVersion" => unsupported,
                       "io.modelcontextprotocol/clientCapabilities" => Dict())))
    r = raw_post(payload; headers=["MCP-Protocol-Version" => unsupported, "Mcp-Method" => "tools/list"])
    @test r.status == 400
    error = parsebody(r)["error"]
    @test error["code"] == -32022
    @test error["data"]["supported"] == ["2026-07-28"]
    @test error["data"]["requested"] == unsupported
end

@testset "Mcp-Name base64 encoding" begin
    encoded = "=?base64?" * base64encode("add_numbers") * "?="
    call_params = Dict("_meta" => req_meta(), "name" => "add_numbers", "arguments" => Dict("a" => 4, "b" => 5))
    r = rpc("tools/call", call_params; extra_headers=["Mcp-Name" => encoded])
    @test r.status == 200
    @test parsebody(r)["result"]["structuredContent"] == 9

    @test MCP.decode_header_value(encoded) == "add_numbers"
    @test MCP.decode_header_value("add_numbers") == "add_numbers"
    @test MCP.decode_header_value("=?base64?YWJj?=") == "abc"
    @test MCP.decode_header_value("=?base64?" * base64encode("Hello, 世界") * "?=") == "Hello, 世界"
end

@testset "transport semantics" begin
    # notifications -> 202 with no body
    notification = Dict("jsonrpc" => "2.0", "method" => "tools/list", "params" => Dict("_meta" => req_meta()))
    r = raw_post(notification; headers=["MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list"])
    @test r.status == 202

    # unknown JSON-RPC method -> 404 + -32601
    r = rpc("does/not/exist", Dict("_meta" => req_meta()))
    @test r.status == 404
    @test parsebody(r)["error"]["code"] == -32601

    # GET / DELETE -> 405
    @test HTTP.request("GET", "$localhost/mcp"; status_exception=false, client=MCP_CLIENT).status == 405
    @test HTTP.request("DELETE", "$localhost/mcp"; status_exception=false, client=MCP_CLIENT).status == 405

    # invalid JSON -> 400 + -32700
    r = HTTP.request("POST", "$localhost/mcp",
        ["Content-Type" => "application/json", "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list"],
        "{ not json"; status_exception=false, client=MCP_CLIENT)
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32700
end

@testset "stdio transport" begin
    notification = Dict("jsonrpc" => "2.0", "method" => "tools/list", "params" => Dict("_meta" => req_meta()))
    messages = [
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "server/discover", "params" => Dict("_meta" => req_meta()))),
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 2, "method" => "tools/call", "params" => Dict("_meta" => req_meta(), "name" => "add_numbers", "arguments" => Dict("a" => 2, "b" => 5)))),
        JSON.json(notification),                # notification -> no response
        "not json",                             # parse error
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 3, "method" => "does/not/exist", "params" => Dict("_meta" => req_meta()))),
    ]
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(join(messages, "\n") * "\n"), output=output)
    lines = split(strip(String(take!(output))), "\n")
    @test length(lines) == 4  # id 1, id 2, parse error, id 3 (notification produced nothing)

    discover = JSON.parse(lines[1])
    @test discover["id"] == 1
    @test discover["result"]["supportedVersions"] == ["2026-07-28"]

    call = JSON.parse(lines[2])
    @test call["result"]["structuredContent"] == 7

    @test JSON.parse(lines[3])["error"]["code"] == -32700
    @test JSON.parse(lines[4])["error"]["code"] == -32601
end

@testset "stdio metadata validation" begin
    # no headers on stdio, but _meta is still required
    missing_meta = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => Dict())
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json(missing_meta) * "\n"), output=output)
    @test JSON.parse(String(take!(output)))["error"]["code"] == -32602

    unsupported = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list",
                       "params" => Dict("_meta" => Dict(
                           "io.modelcontextprotocol/protocolVersion" => "1900-01-01",
                           "io.modelcontextprotocol/clientCapabilities" => Dict())))
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json(unsupported) * "\n"), output=output)
    @test JSON.parse(String(take!(output)))["error"]["code"] == -32022
end

@testset "origin guard" begin
    params = Dict("_meta" => req_meta())
    # disallowed origin
    r = rpc("tools/list", params; extra_headers=["Origin" => "http://evil.example.com"])
    @test r.status == 403

    # same-host origin is allowed
    r = rpc("tools/list", params; extra_headers=["Origin" => "http://$HOST:$PORT"])
    @test r.status == 200

    # explicitly allow-listed origin
    push!(CONTEXT[].mcp.allowed_origins, "http://allowed.example.com")
    r = rpc("tools/list", params; extra_headers=["Origin" => "http://allowed.example.com"])
    @test r.status == 200
    empty!(CONTEXT[].mcp.allowed_origins)
end

@testset "wire name collision" begin
    error = try
        tool("duplicate", Dict(), add_numbers)
        nothing
    catch e
        e
    end
    @test error isa ArgumentError
end

### Instance isolation ########################################################

app = Oxygen.instance()

app.tool("Instance only tool", Dict(:value => "a value"); name="iso_tool") do value::Int
    return value * 2
end

app_ctx = app.custom_module.CONTEXT[]

@testset "instance isolation" begin
    @test haskey(app_ctx.mcp.tools, "iso_tool")
    # the tool registered in the primary context is not visible on the instance
    @test !haskey(app_ctx.mcp.tools, "add_numbers")
    # the tool registered on the instance is not visible in the primary context
    @test !haskey(CONTEXT[].mcp.tools, "iso_tool")
end

app.serve(port=PORT + 1, async=true, show_banner=false, show_errors=false, access_log=nothing)

@testset "instance endpoint isolation" begin
    headers = ["Content-Type" => "application/json", "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list"]
    payload = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => Dict("_meta" => req_meta()))
    r = HTTP.request("POST", "http://$HOST:$(PORT + 1)/mcp", headers, JSON.json(payload);
                     status_exception=false, client=MCP_CLIENT)
    names = [tool["name"] for tool in JSON.parse(String(r.body))["result"]["tools"]]
    @test names == ["iso_tool"]

    r = rpc("tools/list", Dict("_meta" => req_meta()))
    names = [tool["name"] for tool in parsebody(r)["result"]["tools"]]
    @test !("iso_tool" in names)
end

app.terminate()

### Teardown ##################################################################

terminate()

### Custom mount path behind a reverse-proxy prefix ##########################

serve(port=PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing, mcp_path="tools/mcp", prefix="/api", context=AppState("injected"))

@testset "custom mcp path behind a prefix" begin
    payload = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list",
                   "params" => Dict("_meta" => req_meta()))
    headers = ["Content-Type" => "application/json",
               "MCP-Protocol-Version" => "2026-07-28",
               "Mcp-Method" => "tools/list"]
    # fresh client: the module-level client may hold sockets for the prior server
    client = HTTP.Client()

    # reachable through the prefixed external path
    r = HTTP.request("POST", "http://$HOST:$PORT/api/tools/mcp", headers, JSON.json(payload);
                     status_exception=false, client=client)
    @test r.status == 200
    @test length(JSON.parse(String(r.body))["result"]["tools"]) > 0

    # without the prefix the request is rejected by the prefix middleware
    r = HTTP.request("POST", "http://$HOST:$PORT/tools/mcp", headers, JSON.json(payload);
                     status_exception=false, client=client)
    @test r.status == 404
end

terminate()

@testset "normalize_mcp_path" begin
    @test Oxygen.Core.normalize_mcp_path("mcp") == "/mcp"
    @test Oxygen.Core.normalize_mcp_path("/mcp/") == "/mcp"
    @test Oxygen.Core.normalize_mcp_path("  tools/mcp  ") == "/tools/mcp"
    @test Oxygen.Core.normalize_mcp_path("") == "/mcp"
    @test Oxygen.Core.normalize_mcp_path("/") == "/"
end

@testset "resetstate clears tools" begin
    Oxygen.tool("Resettable", Dict(), () -> "x"; name="resettable")
    @test haskey(Oxygen.CONTEXT[].mcp.tools, "resettable")
    Oxygen.resetstate()
    @test isempty(Oxygen.CONTEXT[].mcp.tools)
end

end
