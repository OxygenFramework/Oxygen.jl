module MCPResourceTests

using Test
using HTTP
using JSON
using Base64
using Oxygen; @oxidize
using ..Constants

const MCP = Oxygen.Core.MCP

### Registered resources ###

@resource "oxygen://readme" "Project readme" function readme()
    return "# Oxygen"
end

# The two-argument @resource form uses the handler's docstring as the description
"""
Greeting resource.
"""
@resource "oxygen://greeting" function greeting()
    return "hello"
end

@resource "oxygen://context" "Reads the injected context" function context_resource(; context)
    return context isa Missing ? "missing" : context.label
end

@resource "oxygen://request" "Reads the injected request" function request_resource(; request)
    return string(request.method)
end

@resource "oxygen://binary" "Binary payload" function binary_resource()
    return UInt8[0xff, 0x00, 0x01]
end

@resource "oxygen://response" "HTTP text response" function response_resource()
    return text("plain response")
end

@resource "oxygen://response-binary" "HTTP binary response" function response_binary_resource()
    return HTTP.Response(200, ["Content-Type" => "application/octet-stream"], UInt8[0x00, 0x01])
end

@resource "oxygen://multiple" "Multiple contents" function multiple_resource()
    return ["first", "second"]
end

@resource "oxygen://shaped" "Pre-shaped contents" function shaped_resource()
    return Dict("contents" => [Dict("uri" => "oxygen://shaped", "text" => "shaped")])
end

@resource "oxygen://json" "JSON payload" function json_resource()
    return Dict("a" => 1)
end

@resource "oxygen://throws" "Always throws" function throws_resource()
    error("boom")
end

@resource "oxygen://block" "Block form resource" begin
    function block_resource()
        return "block"
    end
end

# function + resource form with explicit metadata
function meta_resource()
    return "meta"
end

resource("oxygen://meta", "With metadata", meta_resource;
         name="meta_resource", title="Meta", mime_type="text/markdown", size=42)

# do..block form with an explicit wire name
resource("oxygen://do", "Do block resource"; name="do_resource") do
    return "do"
end

# The docstring form of the function API
"""
Function docstring resource.
"""
@resource "oxygen://documented" function documented_resource()
    return "documented"
end

### Registered resource templates ###

@resource "oxygen://docs/{page}" "Docs page" function docs_resource(page::String)
    return "docs for $page"
end

@resource "oxygen://users/{id}/posts/{post}" "User post" function user_post_resource(id::Int, post::String)
    return "user=$id post=$post"
end

# template variables may be keyword arguments; captured values are strings
@resource "oxygen://kw/{term}" "Keyword template" function keyword_resource(; term)
    return "term=$term"
end

@resource "oxygen://typed/{value}" "Typed template" function typed_resource(value::Int)
    return value * 2
end

# An exact static registration wins over a template that would also match
@resource "oxygen://exact/x" "Exact match" function exact_resource()
    return "static"
end

@resource "oxygen://exact/{id}" "Template overlap" function overlap_resource(id::String)
    return "template:$id"
end

### Request helpers ###########################################################

struct AppState
    label::String
end

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

function read_uri(uri::String; extra_headers=[])::HTTP.Response
    params = Dict("_meta" => req_meta(), "uri" => uri)
    return rpc("resources/read", params; extra_headers=vcat(["Mcp-Name" => uri], extra_headers))
end

parsebody(r::HTTP.Response) = JSON.parse(String(r.body))

serve(port=PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing, context=AppState("injected"))

### Tests #####################################################################

@testset "resource registry" begin
    @test haskey(CONTEXT[].mcp.resources, "oxygen://readme")
    @test haskey(CONTEXT[].mcp.resource_templates, "oxygen://docs/{page}")
    @test !haskey(CONTEXT[].mcp.resource_templates, "oxygen://readme")
    @test !haskey(CONTEXT[].mcp.resources, "oxygen://docs/{page}")

    # wire name defaults to the handler name
    @test CONTEXT[].mcp.resources["oxygen://readme"].name == "readme"
    @test CONTEXT[].mcp.resources["oxygen://readme"].description == "Project readme"

    # explicit metadata
    meta = CONTEXT[].mcp.resources["oxygen://meta"]
    @test meta.name == "meta_resource"
    @test meta.title == "Meta"
    @test meta.mime_type == "text/markdown"
    @test meta.size == 42

    # docstring description
    @test CONTEXT[].mcp.resources["oxygen://documented"].description == "Function docstring resource."

    # do-block form
    @test CONTEXT[].mcp.resources["oxygen://do"].name == "do_resource"

    # template variables are extracted in order
    @test CONTEXT[].mcp.resource_templates["oxygen://users/{id}/posts/{post}"].vars == ["id", "post"]
end

@testset "registration validation" begin
    # duplicate URIs (static and template)
    @test_throws ArgumentError resource("oxygen://readme", "duplicate", () -> "x")
    @test_throws ArgumentError resource("oxygen://docs/{page}", "duplicate", (page::String) -> page)

    # a static resource handler cannot declare arguments
    @test_throws ArgumentError resource("oxygen://bad-static", "bad", (x::Int) -> x)

    # template variables and handler parameters must line up
    @test_throws ArgumentError resource("oxygen://bad/{x}", "bad", (y::String) -> y)
    @test_throws ArgumentError resource("oxygen://bad/{x}/{y}", "bad", (x::String) -> x)

    # only simple `{var}` expressions with identifier-safe names
    @test_throws ArgumentError resource("oxygen://bad/{+x}", "bad", () -> "x")
    @test_throws ArgumentError resource("oxygen://bad/{x", "bad", (x::String) -> x)
    @test_throws ArgumentError resource("oxygen://bad/x}", "bad", () -> "x")

    # resources are not streamed
    @test_throws ArgumentError resource("oxygen://bad-stream", "bad", (; stream) -> stream)

    # malformed URIs
    @test_throws ArgumentError resource("", "bad", () -> "x")
    @test_throws ArgumentError resource("oxygen://bad uri", "bad", () -> "x")
end

@testset "server/discover advertises resources" begin
    r = rpc("server/discover", Dict("_meta" => req_meta()))
    result = parsebody(r)["result"]
    @test haskey(result["capabilities"], "resources")
    @test result["capabilities"]["resources"]["subscribe"] == true
    @test result["capabilities"]["resources"]["listChanged"] == true
end

@testset "resources/list" begin
    r = rpc("resources/list", Dict("_meta" => req_meta()))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["ttlMs"] == 0
    @test result["cacheScope"] == "public"

    # templates are listed separately
    @test !any(entry -> haskey(entry, "uriTemplate"), result["resources"])

    uris = [entry["uri"] for entry in result["resources"]]
    @test uris == sort(uris)
    @test "oxygen://readme" in uris
    @test "oxygen://meta" in uris

    readme = only(filter(entry -> entry["uri"] == "oxygen://readme", result["resources"]))
    @test readme["name"] == "readme"
    @test readme["description"] == "Project readme"

    meta = only(filter(entry -> entry["uri"] == "oxygen://meta", result["resources"]))
    @test meta["title"] == "Meta"
    @test meta["mimeType"] == "text/markdown"
    @test meta["size"] == 42

    greeting = only(filter(entry -> entry["uri"] == "oxygen://greeting", result["resources"]))
    @test greeting["description"] == "Greeting resource."
end

@testset "resources/templates/list" begin
    r = rpc("resources/templates/list", Dict("_meta" => req_meta()))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["ttlMs"] == 0
    @test result["cacheScope"] == "public"

    @test all(entry -> haskey(entry, "uriTemplate"), result["resourceTemplates"])
    templates = [entry["uriTemplate"] for entry in result["resourceTemplates"]]
    @test templates == sort(templates)

    docs = only(filter(entry -> entry["uriTemplate"] == "oxygen://docs/{page}", result["resourceTemplates"]))
    @test docs["name"] == "docs_resource"
    @test docs["description"] == "Docs page"
end

@testset "resources/read" begin
    # text content
    result = parsebody(read_uri("oxygen://readme"))["result"]
    @test result["resultType"] == "complete"
    @test result["ttlMs"] == 0
    @test result["cacheScope"] == "private"
    content = only(result["contents"])
    @test content["uri"] == "oxygen://readme"
    @test content["text"] == "# Oxygen"
    @test content["mimeType"] == "text/plain"
    @test !haskey(content, "blob")

    # a declared mime_type is the fallback for text results
    content = only(parsebody(read_uri("oxygen://meta"))["result"]["contents"])
    @test content["mimeType"] == "text/markdown"
    @test content["text"] == "meta"

    # raw bytes become a base64 blob for non-textual media
    bytes = UInt8[0xff, 0x00, 0x01]
    content = only(parsebody(read_uri("oxygen://binary"))["result"]["contents"])
    @test content["mimeType"] == HTTP.sniff(bytes)
    @test content["blob"] == base64encode(bytes)
    @test !haskey(content, "text")

    # HTTP.Response values honor their Content-Type
    content = only(parsebody(read_uri("oxygen://response"))["result"]["contents"])
    @test content["mimeType"] == "text/plain"
    @test content["text"] == "plain response"

    content = only(parsebody(read_uri("oxygen://response-binary"))["result"]["contents"])
    @test content["mimeType"] == "application/octet-stream"
    @test content["blob"] == base64encode(UInt8[0x00, 0x01])

    # a vector of values becomes multiple contents
    contents = parsebody(read_uri("oxygen://multiple"))["result"]["contents"]
    @test [c["text"] for c in contents] == ["first", "second"]

    # an already-shaped result passes through
    result = parsebody(read_uri("oxygen://shaped"))["result"]
    @test only(result["contents"])["text"] == "shaped"

    # anything else is JSON-encoded text
    content = only(parsebody(read_uri("oxygen://json"))["result"]["contents"])
    @test content["mimeType"] == "application/json"
    @test JSON.parse(content["text"]) == Dict("a" => 1)

    # injected context and request
    @test only(parsebody(read_uri("oxygen://context"))["result"]["contents"])["text"] == "injected"
    @test only(parsebody(read_uri("oxygen://request"))["result"]["contents"])["text"] == "POST"

    # block form
    @test only(parsebody(read_uri("oxygen://block"))["result"]["contents"])["text"] == "block"
end

@testset "resource templates" begin
    # a template captures URI segments
    content = only(parsebody(read_uri("oxygen://docs/intro"))["result"]["contents"])
    @test content["text"] == "docs for intro"
    @test content["uri"] == "oxygen://docs/intro"

    # multiple variables, with type coercion
    content = only(parsebody(read_uri("oxygen://users/7/posts/first"))["result"]["contents"])
    @test content["text"] == "user=7 post=first"

    # keyword template variables
    content = only(parsebody(read_uri("oxygen://kw/abc"))["result"]["contents"])
    @test content["text"] == "term=abc"

    # declared parameter types coerce the captured string
    content = only(parsebody(read_uri("oxygen://typed/21"))["result"]["contents"])
    @test content["text"] == "42"

    # captured values are percent-decoded
    content = only(parsebody(read_uri("oxygen://docs/hello%20world"))["result"]["contents"])
    @test content["text"] == "docs for hello world"

    content = only(parsebody(read_uri("oxygen://docs/a%2Fb"))["result"]["contents"])
    @test content["text"] == "docs for a/b"

    # a template variable does not span an unencoded `/`
    r = raw_post(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "resources/read",
                      "params" => Dict("uri" => "oxygen://docs/a/b")))
    @test parsebody(r)["error"]["code"] == -32002

    # an exact registration wins over a template
    @test only(parsebody(read_uri("oxygen://exact/x"))["result"]["contents"])["text"] == "static"
    @test only(parsebody(read_uri("oxygen://exact/y"))["result"]["contents"])["text"] == "template:y"
end

@testset "resource errors" begin
    # unknown URI: modern requests use -32602
    r = read_uri("oxygen://nope")
    @test r.status == 200
    body = parsebody(r)
    @test body["error"]["code"] == -32602
    @test body["error"]["message"] == "Resource not found"
    @test body["error"]["data"]["uri"] == "oxygen://nope"

    # a handler exception is an internal error
    body = parsebody(read_uri("oxygen://throws"))
    @test body["error"]["code"] == -32603
    @test occursin("boom", body["error"]["message"])
end

@testset "modern Mcp-Name validation" begin
    params = Dict("_meta" => req_meta(), "uri" => "oxygen://readme")

    # the Mcp-Name header is required for resources/read
    r = rpc("resources/read", params)
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # ...and must match the body URI
    r = rpc("resources/read", params; extra_headers=["Mcp-Name" => "oxygen://other"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32020

    # non-ASCII URIs are carried in the Base64 sentinel format
    uri = "oxygen://docs/héllo"
    encoded = "=?base64?" * base64encode(uri) * "?="
    r = rpc("resources/read", Dict("_meta" => req_meta(), "uri" => uri);
            extra_headers=["Mcp-Name" => encoded])
    @test r.status == 200
    @test only(parsebody(r)["result"]["contents"])["text"] == "docs for héllo"
end

@testset "legacy resource requests" begin
    init = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                "params" => Dict("protocolVersion" => "2025-11-25",
                                 "capabilities" => Dict(),
                                 "clientInfo" => Dict("name" => "legacy", "version" => "1.0")))
    result = parsebody(raw_post(init))["result"]
    @test result["capabilities"]["resources"]["subscribe"] == true
    @test result["capabilities"]["resources"]["listChanged"] == true

    # legacy list results carry neither the modern envelope nor cache hints
    list = Dict("jsonrpc" => "2.0", "id" => 2, "method" => "resources/list", "params" => Dict())
    result = parsebody(raw_post(list))["result"]
    @test !haskey(result, "resultType")
    @test !haskey(result, "ttlMs")
    @test "oxygen://readme" in [entry["uri"] for entry in result["resources"]]

    # legacy reads need neither headers nor _meta
    read = Dict("jsonrpc" => "2.0", "id" => 3, "method" => "resources/read",
                "params" => Dict("uri" => "oxygen://readme"))
    content = only(parsebody(raw_post(read))["result"]["contents"])
    @test content["text"] == "# Oxygen"

    # legacy not-found uses the dedicated -32002
    read = Dict("jsonrpc" => "2.0", "id" => 4, "method" => "resources/read",
                "params" => Dict("uri" => "oxygen://nope"))
    body = parsebody(raw_post(read))
    @test body["error"]["code"] == -32002
    @test body["error"]["data"]["uri"] == "oxygen://nope"

    # a missing URI is invalid params regardless of era
    read = Dict("jsonrpc" => "2.0", "id" => 5, "method" => "resources/read", "params" => Dict())
    @test parsebody(raw_post(read))["error"]["code"] == -32602
end

@testset "stdio resource requests" begin
    messages = [
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "resources/list",
                       "params" => Dict("_meta" => req_meta()))),
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 2, "method" => "resources/templates/list",
                       "params" => Dict("_meta" => req_meta()))),
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 3, "method" => "resources/read",
                       "params" => Dict("_meta" => req_meta(), "uri" => "oxygen://docs/stdio"))),
    ]
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(join(messages, "\n") * "\n"), output=output)
    lines = split(strip(String(take!(output))), "\n")
    @test length(lines) == 3

    list = JSON.parse(lines[1])["result"]
    @test "oxygen://readme" in [entry["uri"] for entry in list["resources"]]
    templates = JSON.parse(lines[2])["result"]
    @test "oxygen://docs/{page}" in [entry["uriTemplate"] for entry in templates["resourceTemplates"]]
    content = only(JSON.parse(lines[3])["result"]["contents"])
    @test content["text"] == "docs for stdio"
end

### Instance isolation ########################################################

resource_app = Oxygen.instance()
resource_app.resource("iso://only", "Instance resource", () -> "iso"; name="iso_resource")

resource_ctx = resource_app.custom_module.CONTEXT[]

@testset "instance resource isolation" begin
    @test haskey(resource_ctx.mcp.resources, "iso://only")
    @test !haskey(resource_ctx.mcp.resources, "oxygen://readme")
    @test !haskey(CONTEXT[].mcp.resources, "iso://only")
end

# an instance with only resources still mounts the endpoint
resource_app.serve(port=PORT + 5, async=true, show_banner=false, show_errors=false, access_log=nothing)

@testset "resource-only endpoint" begin
    client = HTTP.Client()
    params = Dict("_meta" => req_meta())
    headers = ["Content-Type" => "application/json",
               "MCP-Protocol-Version" => MCP.PROTOCOL_VERSION,
               "Mcp-Method" => "resources/list"]
    payload = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "resources/list", "params" => params)
    r = HTTP.request("POST", "http://$HOST:$(PORT + 5)/mcp", headers, JSON.json(payload);
                     status_exception=false, client=client)
    @test r.status == 200
    result = JSON.parse(String(r.body))["result"]
    @test [entry["uri"] for entry in result["resources"]] == ["iso://only"]
end

resource_app.terminate()

### Teardown ##################################################################

terminate()

end
