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

@kwdef struct Region
    name::String
    sites::Dict{String,Coordinates} = Dict{String,Coordinates}()
end

@enum Color red = 1 blue = 2 green = 3

# Enum containers exercising every nesting shape: struct fields, arrays, maps
# and nullable unions; the plain variant has no keyword constructor.
@kwdef struct Palette
    primary::Color = red
    colors::Vector{Color} = Color[]
    labels::Dict{String,Color} = Dict{String,Color}()
    accent::Union{Color,Nothing} = nothing
end

struct PlainPalette
    primary::Color
    colors::Vector{Color}
    labels::Dict{String,Color}
    accent::Union{Color,Nothing}
end

@kwdef struct PaletteBox
    palette::Palette = Palette()
    alternatives::Vector{Palette} = Palette[]
end

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

@tool "Takes a dictionary" Dict(:sites => "sites by name") function dict_tool(sites::Dict{String,Coordinates})
    return length(sites)
end

@tool "Takes a region" Dict(:region => "a region") function region_tool(region::Region)
    return length(region.sites)
end

@tool "Takes mixed items" Dict(:items => "mixed items") function mixed_tool(items::Vector{Union{Coordinates,Place,Nothing}})
    return length(items)
end

@tool "Takes a vector" Dict(:nums => "numbers") function vector_tool(nums::Vector{Int})
    return sum(nums)
end

@tool "Takes enum collections" Dict(
    :colors => "colors",
    :labels => "colors by label"
    ) function enum_collections_tool(colors::Vector{Color}, labels::Dict{String,Color})
    return length(colors) + length(labels)
end

@tool "Takes a nested enum palette" Dict(:palette => "a palette") function palette_tool(palette::Palette)
    return string(palette.primary)
end

@tool "Takes a plain nested enum palette" Dict(:palette => "a palette") function plain_palette_tool(palette::PlainPalette)
    return string(palette.primary)
end

@tool "Takes a box of palettes" Dict(:box => "a palette box") function palette_box_tool(box::PaletteBox)
    return length(box.alternatives)
end

@tool "Returns a nested enum palette" Dict(:palette => "a palette") function echo_palette(palette::Palette)
    return palette
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

@tool "Returns HTML" Dict() function html_tool()
    return html("<h1>hi</h1>")
end

@tool "Returns an image response" Dict() function image_tool()
    return HTTP.Response(200, ["Content-Type" => "image/png"], UInt8[0x89, 0x50, 0x4e, 0x47])
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

# NamedTuple parameters (wire names default to the Julia parameter names)
@tool "Named tuple parameters" (left = "the left", right = "the right") function named_params(left::Int, right::Int)
    return left + right
end

# A vector of Pairs is accepted as well
@tool "Pair vector parameters" [:x => "the x"] function pair_params(x::Int)
    return x
end

# The two-argument @tool form uses the handler's docstring as the description
"""
Adds two integers using the docstring as the tool description.
"""
@tool Dict(:a => "left", :b => "right") function documented_tool(a::Int, b::Int)
    return a + b
end

# ...and an undocumented handler simply gets an empty description
@tool Dict(:x => "the x") function undocumented_tool(x::Int)
    return x
end

### Registered prompts ###

# arguments are inferred from the signature: `city` required, `tone` optional
@prompt "Report on a city" function city_report(city::String, tone::String="formal")
    return "Write a $tone report about $city"
end

@prompt "Review code" function code_review(language::String, code::String)
    return ["user" => "Please review this $language code:", "user" => "```$language\n$code\n```"]
end

@prompt "Reads the injected context" function context_prompt(; context)
    return context isa Missing ? "missing" : context.label
end

@prompt "Block form prompt" begin
    function block_prompt(value::Int)
        return "value is $value"
    end
end

# function + prompt form with an explicit wire name
function explain(term::String)
    return "Explain $term"
end
prompt("Explain a term", explain; name="explain_term")

"""
Explains a term using the docstring as the prompt description.
"""
function documented_explain(term::String)
    return "Explain $term"
end

# function + prompt form without a description falls back to the docstring
prompt(documented_explain; name="documented_explain")

# do..block form with an explicit wire name
prompt("Greets a person"; name="greet") do name::String
    return "Hello $name"
end

@prompt "Returns an HTTP.Response" function html_prompt()
    return html("<p>hi</p>")
end

@prompt "Returns an assistant image message" function image_prompt(label::String)
    return ["assistant" => Dict("type" => "image", "data" => "aGk=", "mimeType" => "image/png"),
            "user" => label]
end

@prompt "Returns an invalid role" function bad_role_prompt()
    return "system" => "nope"
end

# The two-argument @prompt form uses the handler's docstring as the description
"""
Summarizes a document using the docstring as the prompt description.
"""
@prompt function documented_prompt(document::String)
    return "Summarize $document"
end

# ...and an undocumented handler simply gets an empty description
@prompt function undocumented_prompt(topic::String)
    return "Talk about $topic"
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

function prompt_get(name::String, arguments::AbstractDict; extra_headers=[])::HTTP.Response
    params = Dict("_meta" => req_meta(), "name" => name, "arguments" => arguments)
    return rpc("prompts/get", params; extra_headers=vcat(["Mcp-Name" => name], extra_headers))
end

parsebody(r::HTTP.Response) = JSON.parse(String(r.body))

serve(port=PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing, context=AppState("injected"))

### Tests #####################################################################

@testset "tool registry" begin
    tools = CONTEXT[].mcp.tools
    for name in ["add_numbers", "concatenate", "with_default", "no_args", "enum_tool",
                 "struct_tool", "dict_tool", "region_tool", "mixed_tool", "vector_tool",
                 "enum_collections_tool", "palette_tool", "plain_palette_tool", "palette_box_tool",
                 "echo_palette",
                 "throws_tool", "context_tool", "request_tool", "block_tool", "response_tool",
                 "echo_place", "subtract", "multiply"]
        @test haskey(tools, name)
    end

    # macros and tool are the only write paths; nothing leaked into the global context
    @test !haskey(Oxygen.CONTEXT[].mcp.tools, "add_numbers")
end

@testset "mcp explorer docs page" begin
    r = internalrequest(HTTP.Request("GET", "/docs/mcp"))
    @test r.status == 200
    body = text(r)
    @test occursin("McpExplorer", body)
    @test occursin("endpoint: \"/mcp\"", body)
    # The shipped compass icon is inlined as the page favicon.
    @test occursin("<link rel=\"icon\" type=\"image/svg+xml\" href=\"data:image/svg+xml;base64,", body)
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

    # enums advertise their instance names (the JSON-body wire form); the
    # integer values never appear on the wire
    enum_schema = MCP.inputschema(CONTEXT[].mcp.tools["enum_tool"])
    @test enum_schema["properties"]["color"]["enum"] == ["red", "blue", "green"]
    @test enum_schema["properties"]["color"]["type"] == "string"

    vec_schema = MCP.inputschema(CONTEXT[].mcp.tools["vector_tool"])
    @test vec_schema["properties"]["nums"]["type"] == "array"
    @test vec_schema["properties"]["nums"]["items"]["type"] == "integer"

    # enums nested in arrays and dictionaries
    collections_schema = MCP.inputschema(CONTEXT[].mcp.tools["enum_collections_tool"])
    color_items = collections_schema["properties"]["colors"]["items"]
    @test color_items["type"] == "string"
    @test color_items["enum"] == ["red", "blue", "green"]
    label_values = collections_schema["properties"]["labels"]["additionalProperties"]
    @test label_values["type"] == "string"
    @test label_values["enum"] == ["red", "blue", "green"]

    struct_schema = MCP.inputschema(CONTEXT[].mcp.tools["struct_tool"])
    @test struct_schema["properties"]["place"]["\$ref"] == "#/\$defs/Place"
    @test haskey(struct_schema["\$defs"], "Place")
    @test haskey(struct_schema["\$defs"], "Coordinates")
    @test !occursin("#/components/schemas/", JSON.json(struct_schema))
    @test struct_schema["\$defs"]["Place"]["properties"]["tags"]["default"] == String[]

    dict_schema = MCP.inputschema(CONTEXT[].mcp.tools["dict_tool"])
    @test dict_schema["properties"]["sites"]["type"] == "object"
    @test dict_schema["properties"]["sites"]["additionalProperties"]["\$ref"] == "#/\$defs/Coordinates"
    @test haskey(dict_schema["\$defs"], "Coordinates")

    region_schema = MCP.inputschema(CONTEXT[].mcp.tools["region_tool"])
    region_props = region_schema["\$defs"]["Region"]["properties"]
    @test region_props["sites"]["type"] == "object"
    @test region_props["sites"]["additionalProperties"]["\$ref"] == "#/\$defs/Coordinates"
    @test region_props["sites"]["default"] == Dict{String,Coordinates}()

    mixed_schema = MCP.inputschema(CONTEXT[].mcp.tools["mixed_tool"])
    mixed_items = mixed_schema["properties"]["items"]["items"]
    @test mixed_items["nullable"] == true
    @test Set(ref["\$ref"] for ref in mixed_items["anyOf"]) ==
          Set(["#/\$defs/Coordinates", "#/\$defs/Place"])

    # enum fields inside registered structs are string enums too, at any depth
    palette_schema = MCP.inputschema(CONTEXT[].mcp.tools["palette_tool"])
    palette_props = palette_schema["\$defs"]["Palette"]["properties"]
    @test palette_props["primary"]["type"] == "string"
    @test palette_props["primary"]["enum"] == ["red", "blue", "green"]
    @test palette_props["primary"]["default"] == "red"
    @test palette_props["colors"]["items"]["enum"] == ["red", "blue", "green"]
    @test palette_props["labels"]["additionalProperties"]["enum"] == ["red", "blue", "green"]
    @test palette_props["accent"]["type"] == "string"
    @test palette_props["accent"]["nullable"] == true

    plain_schema = MCP.inputschema(CONTEXT[].mcp.tools["plain_palette_tool"])
    plain_props = plain_schema["\$defs"]["PlainPalette"]["properties"]
    @test plain_props["primary"]["enum"] == ["red", "blue", "green"]
    @test plain_props["colors"]["items"]["type"] == "string"

    # a struct of structs keeps the string convention inside nested $defs
    box_schema = MCP.inputschema(CONTEXT[].mcp.tools["palette_box_tool"])
    box_props = box_schema["\$defs"]["PaletteBox"]["properties"]
    @test box_props["palette"]["\$ref"] == "#/\$defs/Palette"
    @test box_props["alternatives"]["items"]["\$ref"] == "#/\$defs/Palette"
    @test box_schema["\$defs"]["Palette"]["properties"]["primary"]["type"] == "string"
end

@testset "parameter declaration forms" begin
    tools = CONTEXT[].mcp.tools

    named = tools["named_params"]
    @test named.params[1].description == "the left"
    @test named.params[1].wirename == "left"
    @test named.params[2].description == "the right"
    @test named.params[2].wirename == "right"

    pair = tools["pair_params"]
    @test pair.params[1].description == "the x"
    @test pair.params[1].wirename == "x"

    # invocation uses the Julia parameter names
    r = call_tool("named_params", Dict("left" => 1, "right" => 2))
    @test parsebody(r)["result"]["content"][1]["text"] == "3"
end

@testset "parameter metadata validation" begin
    # a description key that does not name a parameter is rejected
    @test_throws ArgumentError tool("Unknown key", Dict(:nope => "x"), subtract)
    # every parameter must carry a description
    @test_throws ArgumentError tool("Incomplete", Dict(:a => "left"), subtract)
    # the per-parameter (description, name) form is no longer supported
    @test_throws ArgumentError tool("Nested", Dict(:a => (description = "x", name = "y")), subtract)
    # String keys are rejected
    @test_throws ArgumentError tool("String key", Dict("a" => "left"), subtract)
end

@testset "docstring tool description" begin
    tools = CONTEXT[].mcp.tools
    @test tools["documented_tool"].description == "Adds two integers using the docstring as the tool description."
    @test tools["undocumented_tool"].description == ""

    r = call_tool("documented_tool", Dict("a" => 1, "b" => 2))
    @test parsebody(r)["result"]["content"][1]["text"] == "3"
end

@testset "docstring prompt description" begin
    prompts = CONTEXT[].mcp.prompts
    @test prompts["documented_prompt"].description == "Summarizes a document using the docstring as the prompt description."
    @test prompts["undocumented_prompt"].description == ""
    @test prompts["documented_explain"].description == "Explains a term using the docstring as the prompt description."

    r = prompt_get("documented_prompt", Dict("document" => "notes"))
    @test parsebody(r)["result"]["messages"][1]["content"]["text"] == "Summarize notes"
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
    @test MCP.parse_tool_argument(Color, "blue") == blue
    @test MCP.parse_tool_argument(Union{Color, Nothing}, "blue") == blue
    @test_throws ArgumentError MCP.parse_tool_argument(Color, "nope")
    @test_throws ArgumentError MCP.parse_tool_argument(Color, 9)
    @test MCP.parse_tool_argument(Vector{Color}, ["red", 2]) == [red, blue]
    @test MCP.parse_tool_argument(Vector{Dict{String,Color}},
                                  [Dict("a" => "green")]) == [Dict("a" => green)]
    @test MCP.parse_tool_argument(Dict{String,Color}, Dict("a" => "blue")) == Dict("a" => blue)
    @test MCP.parse_tool_argument(Dict{Color,Int}, Dict("red" => 1)) == Dict(red => 1)
    @test MCP.parse_tool_argument(Coordinates, Dict("lat" => 1.0, "lon" => 2.0)) == Coordinates(1.0, 2.0)
    @test MCP.parse_tool_argument(Vector{Int}, [1, 2, 3]) == [1, 2, 3]
    @test MCP.parse_tool_argument(Vector{Int}, ["1", "2"]) == [1, 2]
    @test MCP.parse_tool_argument(Vector{Bool}, ["true", "false"]) == [true, false]
    @test MCP.parse_tool_argument(Vector{Union{Coordinates, Nothing}},
                                  [Dict("lat" => 1.0, "lon" => 2.0), nothing]) == [Coordinates(1.0, 2.0), nothing]
    @test MCP.parse_tool_argument(Vector{Union{Color, Nothing}}, [1, nothing]) == [red, nothing]
    @test MCP.parse_tool_argument(Dict{String,Coordinates},
                                  Dict("a" => Dict("lat" => 1.0, "lon" => 2.0))) ==
          Dict("a" => Coordinates(1.0, 2.0))
    @test MCP.parse_tool_argument(Dict{String,Int}, Dict("a" => "1")) == Dict("a" => 1)
    mixed = MCP.parse_tool_argument(Vector{Union{Coordinates,Place,Nothing}},
                                    [Dict("lat" => 1.0, "lon" => 2.0),
                                     Dict("name" => "x", "coordinates" => Dict("lat" => 1.0, "lon" => 2.0)),
                                     nothing])
    @test length(mixed) == 3
    @test mixed[1] == Coordinates(1.0, 2.0)
    @test mixed[2] isa Place
    @test mixed[2].name == "x"
    @test mixed[2].coordinates == Coordinates(1.0, 2.0)
    @test mixed[3] === nothing

    # deep nesting: enums inside struct fields, arrays, maps and unions
    palette = MCP.parse_tool_argument(Palette, Dict(
        "primary" => "blue",
        "colors" => ["red", 2],
        "labels" => Dict("a" => "green"),
        "accent" => "blue",
    ))
    @test palette.primary == blue
    @test palette.colors == [red, blue]
    @test palette.labels == Dict("a" => green)
    @test palette.accent == blue

    plain = MCP.parse_tool_argument(PlainPalette, Dict(
        "primary" => "green",
        "colors" => ["blue"],
        "labels" => Dict("a" => "red"),
        "accent" => nothing,
    ))
    @test plain.primary == green
    @test plain.colors == [blue]
    @test plain.labels == Dict("a" => red)
    @test plain.accent === nothing

    box = MCP.parse_tool_argument(PaletteBox, Dict(
        "palette" => Dict("primary" => "red"),
        "alternatives" => [Dict("primary" => "green")],
    ))
    @test box.palette.primary == red
    @test box.alternatives[1].primary == green
end

@testset "server/discover" begin
    r = rpc("server/discover", Dict("_meta" => req_meta()))
    @test r.status == 200
    body = parsebody(r)
    result = body["result"]
    @test result["resultType"] == "complete"
    @test result["supportedVersions"] == ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    @test haskey(result["capabilities"], "tools")
    @test haskey(result["capabilities"], "prompts")
    @test result["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "Oxygen"
    @test !haskey(result["_meta"]["io.modelcontextprotocol/serverInfo"], "description")
    @test result["cacheScope"] == "public"
end

@testset "tools/list" begin
    r = rpc("tools/list", Dict("_meta" => req_meta()))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["cacheScope"] == "public"
    @test result["ttlMs"] == 0

    names = [tool["name"] for tool in result["tools"]]
    @test names == sort(names)
    @test "add_numbers" in names
    @test "multiply" in names

    add = only(filter(t -> t["name"] == "add_numbers", result["tools"]))
    @test add["description"] == "Add two integers"
    @test add["inputSchema"]["properties"]["a"]["type"] == "integer"
end

@testset "prompt registry" begin
    prompts = CONTEXT[].mcp.prompts
    for name in ["city_report", "code_review", "context_prompt", "block_prompt",
                 "explain_term", "greet"]
        @test haskey(prompts, name)
    end

    # nothing leaked into the global context
    @test !haskey(Oxygen.CONTEXT[].mcp.prompts, "city_report")
end

@testset "prompt reflection" begin
    city = CONTEXT[].mcp.prompts["city_report"]
    @test city.argnames == [:city, :tone]
    @test Oxygen.Core.isrequired(city.params[1].param)
    @test !Oxygen.Core.isrequired(city.params[2].param)
    @test city.params[2].param.default == "formal"

    ctx_prompt = CONTEXT[].mcp.prompts["context_prompt"]
    @test ctx_prompt.has_context == true
    @test isempty(ctx_prompt.params)  # context is never a template variable
end

@testset "prompts/list" begin
    r = rpc("prompts/list", Dict("_meta" => req_meta()))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["cacheScope"] == "public"
    @test result["ttlMs"] == 0

    names = [p["name"] for p in result["prompts"]]
    @test names == sort(names)
    @test "city_report" in names
    @test "greet" in names

    city = only(filter(p -> p["name"] == "city_report", result["prompts"]))
    @test city["description"] == "Report on a city"
    @test city["arguments"] == [
        Dict("name" => "city", "required" => true),
        Dict("name" => "tone", "required" => false),
    ]
end

@testset "prompts/get" begin
    r = prompt_get("city_report", Dict("city" => "Paris"))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["description"] == "Report on a city"
    @test result["messages"] == [Dict(
        "role" => "user",
        "content" => Dict("type" => "text", "text" => "Write a formal report about Paris"),
    )]

    multi = parsebody(prompt_get("code_review",
        Dict("language" => "Julia", "code" => "1 + 1")))["result"]
    @test length(multi["messages"]) == 2
    @test multi["messages"][1]["content"]["text"] == "Please review this Julia code:"
    @test multi["messages"][2]["content"]["text"] == "```Julia\n1 + 1\n```"

    # explicit wire names from the function and do..block forms
    @test parsebody(prompt_get("explain_term", Dict("term" => "monads")))["result"]["messages"][1]["content"]["text"] == "Explain monads"
    @test parsebody(prompt_get("greet", Dict("name" => "Ada")))["result"]["messages"][1]["content"]["text"] == "Hello Ada"
end

@testset "content serialization (MIME)" begin
    # HTTP.Response with a text mime -> text block
    r = call_tool("response_tool", Dict())
    @test parsebody(r)["result"]["content"][1] == Dict("type" => "text", "text" => "plain response")

    # HTML response -> text block (body extracted, not JSON-encoded)
    r = call_tool("html_tool", Dict())
    @test parsebody(r)["result"]["content"][1] == Dict("type" => "text", "text" => "<h1>hi</h1>")

    # image response -> image block with base64 data
    r = call_tool("image_tool", Dict())
    block = parsebody(r)["result"]["content"][1]
    @test block["type"] == "image"
    @test block["mimeType"] == "image/png"
    @test block["data"] == base64encode(UInt8[0x89, 0x50, 0x4e, 0x47])

    # prompt returning an HTTP.Response gets the same treatment
    msg = parsebody(prompt_get("html_prompt", Dict()))["result"]["messages"][1]
    @test msg["role"] == "user"
    @test msg["content"] == Dict("type" => "text", "text" => "<p>hi</p>")
end

@testset "prompt roles" begin
    @test MCP.normalize_role(:assistant) == "assistant"
    @test MCP.normalize_role("USER") == "user"
    @test_throws ArgumentError MCP.normalize_role("system")

    msgs = parsebody(prompt_get("image_prompt", Dict("label" => "look")))["result"]["messages"]
    @test msgs[1]["role"] == "assistant"
    @test msgs[1]["content"]["type"] == "image"
    @test msgs[2]["role"] == "user"
    @test msgs[2]["content"]["text"] == "look"

    # a handler-authoring bug surfaces as an internal error, server stays up
    err = parsebody(prompt_get("bad_role_prompt", Dict()))
    @test err["error"]["code"] == MCP.MCP_INTERNAL_ERROR
end

@testset "prompts/get errors" begin
    unknown = parsebody(prompt_get("does_not_exist", Dict()))
    @test unknown["error"]["code"] == MCP.MCP_INVALID_PARAMS

    missing_arg = parsebody(prompt_get("city_report", Dict()))
    @test missing_arg["error"]["code"] == MCP.MCP_INVALID_PARAMS
    @test occursin("city", missing_arg["error"]["message"])
end

@testset "prompt context injection" begin
    r = prompt_get("context_prompt", Dict())
    messages = parsebody(r)["result"]["messages"]
    @test messages[1]["content"]["text"] == "injected"
end

@testset "prompt wire name collision" begin
    @test_throws ArgumentError prompt("Duplicate", explain; name="city_report")
end

@testset "tools/call happy path" begin
    r = call_tool("add_numbers", Dict("a" => 2, "b" => 3))
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["resultType"] == "complete"
    @test result["isError"] == false
    @test result["content"][1]["type"] == "text"
    @test result["content"][1]["text"] == "5"
    # scalars have no valid object form, so structuredContent is omitted
    @test !haskey(result, "structuredContent")

    # strings are returned as text only
    r = call_tool("concatenate", Dict("a" => "ab", "b" => "cd"))
    result = parsebody(r)["result"]
    @test result["content"][1]["text"] == "abcd"
    @test !haskey(result, "structuredContent")

    # defaulted positional argument
    r = call_tool("with_default", Dict("x" => 5))
    @test parsebody(r)["result"]["content"][1]["text"] == "15"

    # do..block registered tool
    r = call_tool("multiply", Dict("x" => 6, "y" => 7))
    @test parsebody(r)["result"]["content"][1]["text"] == "42"

    # @tool block form
    r = call_tool("block_tool", Dict("value" => 1))
    @test parsebody(r)["result"]["content"][1]["text"] == "2"

    # function + tool registered tool
    r = call_tool("subtract", Dict("a" => 10, "b" => 4))
    @test parsebody(r)["result"]["content"][1]["text"] == "6"

    # enum argument: the instance name is the wire form, integers still work
    r = call_tool("enum_tool", Dict("color" => "blue"))
    @test parsebody(r)["result"]["content"][1]["text"] == "2"

    r = call_tool("enum_tool", Dict("color" => 2))
    @test parsebody(r)["result"]["content"][1]["text"] == "2"

    r = call_tool("enum_tool", Dict("color" => "nope"))
    @test parsebody(r)["error"]["code"] == MCP.MCP_INVALID_PARAMS

    # enums nested in arrays, dictionaries and structs at call time
    r = call_tool("enum_collections_tool",
                  Dict("colors" => ["red", "blue"], "labels" => Dict("a" => "green")))
    @test parsebody(r)["result"]["content"][1]["text"] == "3"

    r = call_tool("palette_tool", Dict("palette" => Dict(
        "primary" => "blue",
        "colors" => ["red"],
        "labels" => Dict("x" => "green"),
        "accent" => "red",
    )))
    @test parsebody(r)["result"]["content"][1]["text"] == "blue"

    r = call_tool("plain_palette_tool", Dict("palette" => Dict(
        "primary" => "green",
        "colors" => ["blue"],
        "labels" => Dict("x" => "red"),
        "accent" => nothing,
    )))
    @test parsebody(r)["result"]["content"][1]["text"] == "green"

    r = call_tool("palette_box_tool", Dict("box" => Dict(
        "palette" => Dict("primary" => "red"),
        "alternatives" => [Dict("primary" => "blue")],
    )))
    @test parsebody(r)["result"]["content"][1]["text"] == "1"

    # deep enum results serialize by name in both the text block and
    # structuredContent (the same convention as every other JSON response)
    r = call_tool("echo_palette", Dict("palette" => Dict(
        "primary" => "blue",
        "colors" => ["red", "green"],
        "labels" => Dict("x" => "blue"),
        "accent" => "red",
    )))
    result = parsebody(r)["result"]
    text_result = JSON.parse(result["content"][1]["text"])
    @test text_result["primary"] == "blue"
    @test text_result["colors"] == ["red", "green"]
    @test text_result["labels"] == Dict("x" => "blue")
    @test text_result["accent"] == "red"
    @test result["structuredContent"]["primary"] == "blue"
    @test result["structuredContent"]["colors"] == ["red", "green"]
    @test result["structuredContent"]["labels"] == Dict("x" => "blue")
    @test result["structuredContent"]["accent"] == "red"

    # vector argument
    r = call_tool("vector_tool", Dict("nums" => [1, 2, 3, 4]))
    @test parsebody(r)["result"]["content"][1]["text"] == "10"

    # struct argument
    r = call_tool("struct_tool", Dict("place" => Dict(
        "name" => "NYC",
        "coordinates" => Dict("lat" => 40.7, "lon" => -74.0),
    )))
    @test parsebody(r)["result"]["content"][1]["text"] == "NYC"

    # dictionary argument with custom struct values
    r = call_tool("dict_tool", Dict("sites" => Dict("a" => Dict("lat" => 1.0, "lon" => 2.0))))
    @test parsebody(r)["result"]["content"][1]["text"] == "1"

    # struct argument containing a dictionary field
    r = call_tool("region_tool", Dict("region" => Dict(
        "name" => "north",
        "sites" => Dict("a" => Dict("lat" => 1.0, "lon" => 2.0)),
    )))
    @test parsebody(r)["result"]["content"][1]["text"] == "1"

    # vector of mixed custom types (union elements)
    r = call_tool("mixed_tool", Dict("items" => [
        Dict("lat" => 1.0, "lon" => 2.0),
        Dict("name" => "x", "coordinates" => Dict("lat" => 1.0, "lon" => 2.0)),
        nothing,
    ]))
    @test parsebody(r)["result"]["content"][1]["text"] == "3"

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
    result = parsebody(r)["result"]
    @test result["content"][1]["text"] == "2"
    @test !haskey(result, "structuredContent")
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
    @test error["data"]["supported"] == ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    @test error["data"]["requested"] == unsupported
end

@testset "Mcp-Name base64 encoding" begin
    encoded = "=?base64?" * base64encode("add_numbers") * "?="
    call_params = Dict("_meta" => req_meta(), "name" => "add_numbers", "arguments" => Dict("a" => 4, "b" => 5))
    r = rpc("tools/call", call_params; extra_headers=["Mcp-Name" => encoded])
    @test r.status == 200
    @test parsebody(r)["result"]["content"][1]["text"] == "9"

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

    # client responses (result/error + id, no method) -> 202
    client_response = Dict("jsonrpc" => "2.0", "id" => 1, "result" => Dict("ok" => true))
    r = raw_post(client_response)
    @test r.status == 202

    # invalid JSON-RPC shape (no method, no result/error) -> 400 + -32600
    r = raw_post(Dict("jsonrpc" => "2.0", "id" => 1))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # unknown JSON-RPC method -> 404 + -32601
    r = rpc("does/not/exist", Dict("_meta" => req_meta()))
    @test r.status == 404
    @test parsebody(r)["error"]["code"] == -32601

    # ping was removed from the modern era -> 404 + -32601
    r = rpc("ping", Dict("_meta" => req_meta()))
    @test r.status == 404
    @test parsebody(r)["error"]["code"] == -32601

    # GET serves a JSON health body; DELETE -> 405
    r = HTTP.request("GET", "$localhost/mcp"; status_exception=false, client=MCP_CLIENT)
    @test r.status == 200
    @test parsebody(r)["status"] == "ok"
    @test HTTP.request("DELETE", "$localhost/mcp"; status_exception=false, client=MCP_CLIENT).status == 405

    # a modern version header on GET is rejected with 405
    r = HTTP.request("GET", "$localhost/mcp"; headers=["MCP-Protocol-Version" => "2026-07-28"],
                     status_exception=false, client=MCP_CLIENT)
    @test r.status == 405

    # missing / wrong Content-Type -> 415
    r = HTTP.request("POST", "$localhost/mcp", ["Content-Type" => "text/plain"], "{}";
                     status_exception=false, client=MCP_CLIENT)
    @test r.status == 415

    # invalid JSON -> 400 + -32700
    r = HTTP.request("POST", "$localhost/mcp",
        ["Content-Type" => "application/json", "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list"],
        "{ not json"; status_exception=false, client=MCP_CLIENT)
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32700

    # SSE notification stream: held open with a priming comment
    sse_client = HTTP.Client()
    sse_received = Ref("")
    @async begin
        try
            HTTP.open("GET", "$localhost/mcp", ["Accept" => "text/event-stream"]; client=sse_client) do io
                while !eof(io)
                    sse_received[] *= String(readavailable(io))
                    occursin(": connected", sse_received[]) && break
                end
            end
        catch
            # connection closed when the test block exits
        end
    end
    deadline = time() + 5
    while time() < deadline && !occursin(": connected", sse_received[])
        sleep(0.05)
    end
    @test occursin(": connected", sse_received[])
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
    @test discover["result"]["supportedVersions"][1] == "2026-07-28"

    call = JSON.parse(lines[2])
    @test call["result"]["content"][1]["text"] == "7"
    @test call["result"]["resultType"] == "complete"

    @test JSON.parse(lines[3])["error"]["code"] == -32700
    @test JSON.parse(lines[4])["error"]["code"] == -32601
end

@testset "stdio metadata validation" begin
    # no headers on stdio and no _meta: this is a LEGACY request and must succeed
    legacy = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => Dict())
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json(legacy) * "\n"), output=output)
    body = JSON.parse(String(take!(output)))
    @test haskey(body["result"], "tools")
    @test !haskey(body["result"], "resultType")

    # an unsupported version in _meta marks a modern request -> -32022
    unsupported = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list",
                       "params" => Dict("_meta" => Dict(
                           "io.modelcontextprotocol/protocolVersion" => "1900-01-01",
                           "io.modelcontextprotocol/clientCapabilities" => Dict())))
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json(unsupported) * "\n"), output=output)
    @test JSON.parse(String(take!(output)))["error"]["code"] == -32022
end

@testset "legacy initialize handshake (HTTP)" begin
    # initialize echoes a supported legacy version and advertises tools
    init = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                "params" => Dict("protocolVersion" => "2025-06-18",
                                 "capabilities" => Dict(),
                                 "clientInfo" => Dict("name" => "legacy", "version" => "1.0")))
    r = raw_post(init)
    @test r.status == 200
    result = parsebody(r)["result"]
    @test result["protocolVersion"] == "2025-06-18"
    @test haskey(result["capabilities"], "tools")
    @test result["serverInfo"]["name"] == "Oxygen"
    @test result["serverInfo"]["version"] == "1.0.0"
    @test !haskey(result["serverInfo"], "description")
    @test !haskey(result, "resultType")

    # notifications/initialized is accepted silently
    note = Dict("jsonrpc" => "2.0", "method" => "notifications/initialized")
    @test raw_post(note).status == 202

    # tools/list needs neither headers nor _meta in the legacy era
    list = Dict("jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => Dict())
    r = raw_post(list)
    @test r.status == 200
    result = parsebody(r)["result"]
    @test !haskey(result, "resultType")
    @test !haskey(result, "ttlMs")
    @test any(t -> t["name"] == "add_numbers", result["tools"])

    # tools/call needs neither headers nor _meta; an object result keeps
    # structuredContent under 2025-06-18
    call = Dict("jsonrpc" => "2.0", "id" => 3, "method" => "tools/call",
                "params" => Dict("name" => "echo_place", "arguments" => Dict(
                    "place" => Dict("name" => "NYC",
                                    "coordinates" => Dict("lat" => 40.7, "lon" => -74.0)))))
    r = raw_post(call)
    result = parsebody(r)["result"]
    @test result["isError"] == false
    @test result["structuredContent"]["name"] == "NYC"
    @test !haskey(result, "resultType")

    # scalar results carry text only (structuredContent must be an object)
    call = Dict("jsonrpc" => "2.0", "id" => 4, "method" => "tools/call",
                "params" => Dict("name" => "add_numbers", "arguments" => Dict("a" => 4, "b" => 6)))
    result = parsebody(raw_post(call))["result"]
    @test result["content"][1]["text"] == "10"
    @test !haskey(result, "structuredContent")

    # legacy ping returns an empty result object
    ping = Dict("jsonrpc" => "2.0", "id" => 5, "method" => "ping", "params" => Dict())
    @test isempty(parsebody(raw_post(ping))["result"])

    @test MCP.negotiate_version("2025-06-18") == "2025-06-18"
    @test MCP.negotiate_version("1900-01-01") == "2025-11-25"
    @test MCP.negotiate_version(nothing) == "2025-11-25"
end

@testset "legacy structuredContent gating" begin
    place_args = Dict("place" => Dict("name" => "A",
                                      "coordinates" => Dict("lat" => 1.0, "lon" => 2.0)))

    # an object-returning tool keeps structuredContent at >= 2025-06-18
    init = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                "params" => Dict("protocolVersion" => "2025-06-18", "capabilities" => Dict()))
    @test parsebody(raw_post(init))["result"]["protocolVersion"] == "2025-06-18"
    call = Dict("jsonrpc" => "2.0", "id" => 2, "method" => "tools/call",
                "params" => Dict("name" => "echo_place", "arguments" => place_args))
    @test haskey(parsebody(raw_post(call))["result"], "structuredContent")

    # an older revision withholds it
    init = Dict("jsonrpc" => "2.0", "id" => 3, "method" => "initialize",
                "params" => Dict("protocolVersion" => "2024-11-05", "capabilities" => Dict()))
    @test parsebody(raw_post(init))["result"]["protocolVersion"] == "2024-11-05"
    call = Dict("jsonrpc" => "2.0", "id" => 4, "method" => "tools/call",
                "params" => Dict("name" => "echo_place", "arguments" => place_args))
    result = parsebody(raw_post(call))["result"]
    @test !isempty(result["content"])
    @test !haskey(result, "structuredContent")
end

@testset "JSON-RPC envelope validation" begin
    # missing jsonrpc -> -32600
    r = raw_post(Dict("id" => 1, "method" => "ping", "params" => Dict()))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # wrong jsonrpc version -> -32600
    r = raw_post(Dict("jsonrpc" => "1.0", "id" => 1, "method" => "ping", "params" => Dict()))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # structured id -> -32600 (ids are strings or numbers)
    r = raw_post(Dict("jsonrpc" => "2.0", "id" => Dict("x" => 1), "method" => "ping", "params" => Dict()))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # null id -> -32600 (forbidden by the MCP schema)
    r = raw_post(Dict("jsonrpc" => "2.0", "id" => nothing, "method" => "ping", "params" => Dict()))
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # a well-formed notification is still accepted silently
    r = raw_post(Dict("jsonrpc" => "2.0", "method" => "notifications/initialized"))
    @test r.status == 202
end

@testset "legacy HTTP sessions" begin
    ctx = CONTEXT[]
    sid_of(r) = HTTP.header(r, MCP.SESSION_HEADER)
    init(version) = raw_post(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                                  "params" => Dict("protocolVersion" => version, "capabilities" => Dict())))
    echo(sid, id) = raw_post(
        Dict("jsonrpc" => "2.0", "id" => id, "method" => "tools/call",
             "params" => Dict("name" => "echo_place",
                              "arguments" => Dict("place" => Dict("name" => "S",
                                                                  "coordinates" => Dict("lat" => 1.0, "lon" => 2.0)))));
        headers=[MCP.SESSION_HEADER => sid])

    # initialize mints a session and returns its id; header-less initialize also
    # keeps the anonymous state in sync for old clients
    r = init("2024-11-05")
    sid1 = sid_of(r)
    @test r.status == 200
    @test sid1 isa String && !isempty(sid1)
    @test haskey(ctx.mcp.sessions, sid1)
    @test ctx.mcp.session_version[] == "2024-11-05"

    # echoing the id scopes feature gating to the session's negotiated version
    result = parsebody(echo(sid1, 2))["result"]
    @test !haskey(result, "structuredContent")

    # a second session negotiates a newer version independently
    r = init("2025-11-25")
    sid2 = sid_of(r)
    @test sid2 isa String && sid2 != sid1
    @test haskey(parsebody(echo(sid2, 3))["result"], "structuredContent")
    # ...and the first session is unaffected
    @test !haskey(parsebody(echo(sid1, 4))["result"], "structuredContent")

    # an unknown session id is rejected with 404
    r = raw_post(Dict("jsonrpc" => "2.0", "id" => 5, "method" => "ping", "params" => Dict());
                 headers=[MCP.SESSION_HEADER => "00000000-0000-0000-0000-000000000000"])
    @test r.status == 404
    @test parsebody(r)["error"]["code"] == -32600

    # DELETE terminates the session; later requests naming it get 404
    r = HTTP.request("DELETE", "$localhost/mcp", [MCP.SESSION_HEADER => sid2];
                     status_exception=false, client=MCP_CLIENT)
    @test r.status == 200
    @test !haskey(ctx.mcp.sessions, sid2)
    r = raw_post(Dict("jsonrpc" => "2.0", "id" => 6, "method" => "ping", "params" => Dict());
                 headers=[MCP.SESSION_HEADER => sid2])
    @test r.status == 404

    # DELETE without a session header (and the modern era) stay 405
    @test HTTP.request("DELETE", "$localhost/mcp"; status_exception=false, client=MCP_CLIENT).status == 405
    r = HTTP.request("DELETE", "$localhost/mcp", ["Mcp-Session-Id" => sid1, "MCP-Protocol-Version" => "2026-07-28"];
                     status_exception=false, client=MCP_CLIENT)
    @test r.status == 405
    @test haskey(ctx.mcp.sessions, sid1)

    # expired sessions are swept when a new one is minted
    adapter_ctx = Oxygen.Core.ServerContext()
    stale = MCP.MCPSession("stale")
    stale.last_seen = time() - MCP.SESSION_TTL_SECONDS - 1
    lock(adapter_ctx.mcp.sessions_lock) do
        adapter_ctx.mcp.sessions["stale"] = stale
    end
    fresh = MCP.new_session!(adapter_ctx)
    @test !haskey(adapter_ctx.mcp.sessions, "stale")
    @test adapter_ctx.mcp.sessions[fresh.id] === fresh
    @test MCP.legacy_version(adapter_ctx, fresh) == "2025-11-25"
    @test MCP.legacy_version(adapter_ctx, nothing) == adapter_ctx.mcp.session_version[]

    # restore the anonymous default for the tests that follow
    init("2025-11-25")
    ctx.mcp.initialized[] = false
    ctx.mcp.handshake_complete[] = false
end

@testset "JSON-RPC batching (2025-03-26)" begin
    init(version) = raw_post(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                                  "params" => Dict("protocolVersion" => version, "capabilities" => Dict())))
    add_call(id) = Dict("jsonrpc" => "2.0", "id" => id, "method" => "tools/call",
                        "params" => Dict("name" => "add_numbers", "arguments" => Dict("a" => 1, "b" => 2)))
    note = Dict("jsonrpc" => "2.0", "method" => "notifications/initialized")
    unknown = Dict("jsonrpc" => "2.0", "id" => 99, "method" => "does/not/exist")

    # batching was removed after 2025-03-26
    init("2025-11-25")
    r = raw_post([add_call(1)])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # ...and supported under it: responses only for requests, in order
    init("2025-03-26")
    r = raw_post([add_call(1), note, unknown])
    @test r.status == 200
    batch = parsebody(r)
    @test batch isa Vector && length(batch) == 2
    by_id = Dict(entry["id"] => entry for entry in batch)
    @test by_id[1]["result"]["content"][1]["text"] == "3"
    @test by_id[99]["error"]["code"] == -32601

    # an all-notification batch answers 202 with no body
    r = raw_post([note])
    @test r.status == 202
    @test isempty(r.body)

    # malformed entries become per-entry errors instead of failing the batch
    r = raw_post([add_call(2), "nope", Dict("jsonrpc" => "1.0", "id" => 3, "method" => "ping")])
    @test r.status == 200
    batch = parsebody(r)
    @test [entry["id"] for entry in batch] == [2, nothing, 3]
    @test haskey(batch[1], "result")
    @test batch[2]["error"]["code"] == -32600
    @test batch[3]["error"]["code"] == -32600

    # an empty batch is an invalid request
    r = raw_post(Any[])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # the modern era removed batching
    init("2025-11-25")
    r = raw_post([add_call(4)]; headers=["MCP-Protocol-Version" => MCP.PROTOCOL_VERSION,
                                         "Mcp-Method" => "tools/call"])
    @test r.status == 400
    @test parsebody(r)["error"]["code"] == -32600

    # stdio supports batches under the same revision gate
    stdio_initialize = JSON.json(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                                      "params" => Dict("protocolVersion" => "2025-03-26",
                                                       "capabilities" => Dict())))
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(stdio_initialize * "\n"), output=output)
    @test JSON.parse(String(take!(output)))["result"]["protocolVersion"] == "2025-03-26"

    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(JSON.json([add_call(10), note]) * "\n"), output=output)
    batch = JSON.parse(String(take!(output)))
    @test batch isa Vector && length(batch) == 1
    @test batch[1]["id"] == 10
    @test batch[1]["result"]["content"][1]["text"] == "3"
end

@testset "legacy stdio handshake" begin
    messages = [
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                       "params" => Dict("protocolVersion" => "2025-11-25", "capabilities" => Dict()))),
        JSON.json(Dict("jsonrpc" => "2.0", "method" => "notifications/initialized")),
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => Dict())),
        JSON.json(Dict("jsonrpc" => "2.0", "id" => 3, "method" => "tools/call",
                       "params" => Dict("name" => "echo_place", "arguments" => Dict(
                           "place" => Dict("name" => "SFO",
                                           "coordinates" => Dict("lat" => 37.7, "lon" => -122.4)))))),
    ]
    output = IOBuffer()
    MCP.stdio_loop(CONTEXT[]; input=IOBuffer(join(messages, "\n") * "\n"), output=output)
    lines = split(strip(String(take!(output))), "\n")
    @test length(lines) == 3

    init = JSON.parse(lines[1])["result"]
    @test init["protocolVersion"] == "2025-11-25"
    @test !haskey(init, "resultType")

    list = JSON.parse(lines[2])["result"]
    @test haskey(list, "tools")
    @test !haskey(list, "resultType")

    call = JSON.parse(lines[3])["result"]
    @test call["structuredContent"]["name"] == "SFO"
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

    # the legacy GET notification sink enforces the same guard
    r = HTTP.request("GET", "$localhost/mcp",
                     ["Origin" => "http://evil.example.com", "Accept" => "text/event-stream"];
                     status_exception=false, client=MCP_CLIENT)
    @test r.status == 403
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
      access_log=nothing, mcp_path="tools/mcp", mcp_server_name="McpCustom",
      mcp_server_version=v"9.9.9", mcp_server_description="Custom tools server",
      prefix="/api", context=AppState("injected"))

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
    body = JSON.parse(String(r.body))
    @test length(body["result"]["tools"]) > 0

    # the modern result meta advertises the configured server identity
    meta_info = body["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]
    @test meta_info["name"] == "McpCustom"
    @test meta_info["version"] == "9.9.9"
    @test meta_info["description"] == "Custom tools server"

    # so does the legacy initialize handshake
    init = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                "params" => Dict("protocolVersion" => "2025-06-18", "capabilities" => Dict()))
    r = HTTP.request("POST", "http://$HOST:$PORT/api/tools/mcp", ["Content-Type" => "application/json"],
                     JSON.json(init); status_exception=false, client=client)
    @test r.status == 200
    server_info = JSON.parse(String(r.body))["result"]["serverInfo"]
    @test server_info["name"] == "McpCustom"
    @test server_info["version"] == "9.9.9"
    @test server_info["description"] == "Custom tools server"

    # without the prefix the request is rejected by the prefix middleware
    r = HTTP.request("POST", "http://$HOST:$PORT/tools/mcp", headers, JSON.json(payload);
                     status_exception=false, client=client)
    @test r.status == 404

    # the explorer page points at the prefixed endpoint
    r = HTTP.request("GET", "http://$HOST:$PORT/api/docs/mcp"; status_exception=false, client=client)
    @test r.status == 200
    @test occursin("endpoint: \"/api/tools/mcp\"", String(r.body))
end

terminate()

### mcp_server_version must be valid semver ###################################

@testset "mcp server version requires semver" begin
    @test_throws ArgumentError serve(port=PORT, host=HOST, async=true, show_banner=false,
                                     show_errors=false, access_log=nothing,
                                     mcp_server_version="not-a-version")
    @test_throws MethodError serve(port=PORT, host=HOST, async=true, show_banner=false,
                                   show_errors=false, access_log=nothing,
                                   mcp_server_version=1.0)
end

### Top-level mcp = false disables the endpoint ###############################

serve(port=PORT, host=HOST, async=true, show_banner=false, show_errors=false,
      access_log=nothing, mcp=false, mcp_path="/disabled/mcp", context=AppState("injected"))

@testset "mcp disabled at serve" begin
    payload = Dict("jsonrpc" => "2.0", "id" => 1, "method" => "tools/list",
                   "params" => Dict("_meta" => req_meta()))
    headers = ["Content-Type" => "application/json",
               "MCP-Protocol-Version" => "2026-07-28",
               "Mcp-Method" => "tools/list"]
    client = HTTP.Client()
    r = HTTP.request("POST", "http://$HOST:$PORT/disabled/mcp", headers, JSON.json(payload);
                     status_exception=false, client=client)
    @test r.status == 404

    # the explorer page is not mounted either
    r = HTTP.request("GET", "http://$HOST:$PORT/docs/mcp"; status_exception=false, client=client)
    @test r.status == 404
end

terminate()

@testset "resetstate clears tools" begin
    Oxygen.tool("Resettable", Dict(), () -> "x"; name="resettable")
    Oxygen.prompt("Resettable", () -> "x"; name="resettable")
    @test haskey(Oxygen.CONTEXT[].mcp.tools, "resettable")
    @test haskey(Oxygen.CONTEXT[].mcp.prompts, "resettable")
    Oxygen.resetstate()
    @test isempty(Oxygen.CONTEXT[].mcp.tools)
    @test isempty(Oxygen.CONTEXT[].mcp.prompts)
end

end
