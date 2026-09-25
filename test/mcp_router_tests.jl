module MCPRouterTests

using Test
using HTTP
using JSON
using Oxygen; @oxidize
using ..Constants

const MCP = Oxygen.Core.MCP

### Route-backed MCP tools ###

# Router-level metadata is inherited by every route in the group.
const api = router("/users",
    mcp = (
        description = "User management",
        parameters = Dict(:id => "User ID"),
    ),
)

@get api("/{id}", mcp = (description = "Get a user", parameters = Dict(:id => "The user id"))) function route_get_user(req::HTTP.Request, id::Int)
    return "user $id"
end

@post api("/create", mcp = (description = "Create a user", parameters = Dict(:email => "Email address"))) function route_create_user(req::HTTP.Request, email::String)
    return "created $email"
end

# Only a route description: the router description still prefixes it and the
# router's parameter description is inherited.
@get api("/{id}/posts", mcp = (description = "List posts")) function route_list_posts(req::HTTP.Request, id::Int)
    return "posts for $id"
end

# mcp = false excludes an endpoint from the tool registry.
@get api("/health", mcp = false) function route_health(req::HTTP.Request)
    return "ok"
end

# mcp = true enables the endpoint; the function docstring supplies the text.
"""Read the current weather"""
function route_weather(req::HTTP.Request, city::String)
    return "sunny in $city"
end
@get api("/weather", mcp = true) route_weather

# Router-level mcp = true enables every route with default metadata.
const things = router("/things", mcp = true)

@get things("/{id}") function route_get_thing(req::HTTP.Request, id::Int)
    return "thing $id"
end

# Route-level parameter metadata may rename the MCP wire name.
@post things("/rename", mcp = (
    description = "Rename a thing",
    parameters = Dict(:value => (description = "the value", name = "val")),
)) function route_rename_thing(req::HTTP.Request, value::Int)
    return value + 1
end

# An anonymous do-block handler gets an endpoint-derived tool name.
post(api("/anon", mcp = (description = "Anonymous handler",))) do req::HTTP.Request, value::Int
    return value * 3
end

# A router-level name is ignored so it cannot collide across the group.
const named = router("/named", mcp = (description = "Named group", name = "ignored_group_name"))
@get named("/{id}") function route_named(req::HTTP.Request, id::Int)
    return id
end

# Router-level `mcp = false` is authoritative: a route cannot opt back in.
const off = router("/off", mcp = false)
@get off("/{id}", mcp = true) function route_off(req::HTTP.Request, id::Int)
    return id
end

# Untyped leading arguments are bound to the request by the routing layer.
const untyped = router("/untyped", mcp = true)
@get untyped("/{id}") function route_untyped(req, id::Int)
    return "u$id"
end

# Two anonymous handlers whose slug collides are disambiguated.
const coll = router("/coll", mcp = true)
@get coll("/{id}") function(req::HTTP.Request, id::Int)
    return id
end
@get coll("/id") function(req::HTTP.Request)
    return "static"
end

### Request helpers ###########################################################

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

serve(port=PORT, host=HOST, async=true, show_banner=false, show_errors=false, access_log=nothing)

### Tests #####################################################################

@testset "mcp metadata normalization" begin
    @test MCP.normalize_mcp_config(nothing) === nothing
    @test MCP.normalize_mcp_config(false).enabled == false
    @test MCP.normalize_mcp_config(true).enabled == true
    @test MCP.normalize_mcp_config("A description").description == "A description"

    config = MCP.normalize_mcp_config((
        description = "Group",
        parameters = Dict(:id => "ID", :value => (description = "value", name = "val")),
        name = "explicit",
    ))
    @test config.enabled == true
    @test config.description == "Group"
    @test config.parameters == Dict(:id => "ID", :value => "value")
    @test config.names == Dict(:value => "val")
    @test config.toolname == "explicit"

    @test_throws ArgumentError MCP.normalize_mcp_config(42)

    # `parameters` accepts a Dict, a NamedTuple, or a vector of Pairs
    as_named = MCP.normalize_mcp_config((description = "Group",
        parameters = (id = "ID", value = (description = "value", name = "val"))))
    @test as_named.parameters == Dict(:id => "ID", :value => "value")
    @test as_named.names == Dict(:value => "val")

    as_pairs = MCP.normalize_mcp_config((description = "Group", parameters = [:id => "ID"]))
    @test as_pairs.parameters == Dict(:id => "ID")

    # `parse_mcp_parameters` is the shared parser used by `@tool` too
    descriptions, names = MCP.parse_mcp_parameters((a = "first", b = (description = "second", name = "B")))
    @test descriptions == Dict(:a => "first", :b => "second")
    @test names == Dict(:b => "B")

    # router config -> route config resolution
    outer = MCP.normalize_mcp_config((description = "Group", parameters = Dict(:id => "ID")))
    route = MCP.normalize_mcp_config((description = "Route", parameters = Dict(:id => "Override")))
    resolved = MCP.resolve_mcp_config(outer, route)
    @test resolved.description == "Route"
    @test resolved.group == "Group"
    @test resolved.parameters[:id] == "Override"

    # a disabled route excludes itself even when the router enables it
    @test MCP.resolve_mcp_config(outer, MCP.normalize_mcp_config(false)) === nothing

    # a disabled router is authoritative: a route cannot re-enable it
    @test MCP.resolve_mcp_config(MCP.normalize_mcp_config(false), MCP.normalize_mcp_config(true)) === nothing
    @test MCP.resolve_mcp_config(MCP.normalize_mcp_config(false), MCP.normalize_mcp_config((description = "x",))) === nothing
end

@testset "route compatibility" begin
    compat = Oxygen.Core.mcp_compatible_route

    # typed and untyped leading request arguments are both accepted
    @test compat("GET", function(req, id::Int) end)
    @test compat("GET", function(req::HTTP.Request, id::Int) end)
    # a leading non-request argument is not
    @test !compat("GET", function(id::Int) end)
    # no arguments at all is a valid zero-arg tool
    @test compat("GET", function() end)
    # streaming/websocket routes are never exposed
    @test !compat("WEBSOCKET", function(ws) end)
    @test !compat("STREAM", function(stream) end)
end

@testset "route-backed tools" begin
    tools = CONTEXT[].mcp.tools

    # router description prefixes the route description; route parameter
    # descriptions override the router's
    get_user = tools["route_get_user"]
    @test get_user.description == "User management: Get a user"
    @test get_user.inject_request == true
    @test length(get_user.params) == 1
    @test get_user.params[1].wirename == "id"
    @test get_user.params[1].description == "The user id"

    create_user = tools["route_create_user"]
    @test create_user.description == "User management: Create a user"
    @test create_user.params[1].description == "Email address"

    # router parameter descriptions are inherited when the route doesn't override
    list_posts = tools["route_list_posts"]
    @test list_posts.description == "User management: List posts"
    @test list_posts.params[1].description == "User ID"

    # mcp = false excludes the route
    @test !haskey(tools, "route_health")

    # mcp = true + docstring, still grouped by the router description
    @test tools["route_weather"].description == "User management: Read the current weather"

    # router-level mcp = true with no metadata yields a bare tool
    @test haskey(tools, "route_get_thing")
    @test tools["route_get_thing"].description == ""

    # wire-name override
    rename = tools["route_rename_thing"]
    @test rename.params[1].wirename == "val"
    @test rename.params[1].description == "the value"

    schema = MCP.inputschema(rename)
    @test haskey(schema["properties"], "val")
    @test schema["properties"]["val"]["description"] == "the value"

    # an anonymous handler falls back to an endpoint-derived name
    @test haskey(tools, "post_users_anon")
    @test tools["post_users_anon"].description == "User management: Anonymous handler"

    # a router-level name is ignored (only routes may name their tool)
    @test haskey(tools, "route_named")
    @test !haskey(tools, "ignored_group_name")
    @test tools["route_named"].description == "Named group"

    # router-level mcp = false is authoritative; the route cannot opt back in
    @test !haskey(tools, "route_off")

    # untyped request handlers are exposed too
    @test haskey(tools, "route_untyped")
    @test tools["route_untyped"].params[1].wirename == "id"

    # endpoint-derived name collisions are disambiguated rather than dropped
    @test haskey(tools, "get_coll_id")
    @test haskey(tools, "get_coll_id_2")

    # excluded route is not served
    @test !any(t -> t["name"] == "route_health", parsebody(rpc("tools/list", Dict("_meta" => req_meta())))["result"]["tools"])
end

@testset "route-backed tool invocation" begin
    r = call_tool("route_get_user", Dict("id" => 7))
    @test parsebody(r)["result"]["content"][1]["text"] == "user 7"

    r = call_tool("route_create_user", Dict("email" => "a@b.com"))
    @test parsebody(r)["result"]["content"][1]["text"] == "created a@b.com"

    # an untyped request handler is invoked with the request injected
    r = call_tool("route_untyped", Dict("id" => 5))
    @test parsebody(r)["result"]["content"][1]["text"] == "u5"

    # the wire name is used for lookup
    r = call_tool("route_rename_thing", Dict("val" => 41))
    @test parsebody(r)["result"]["content"][1]["text"] == "42"

    # the Julia parameter name is still accepted as a fallback
    r = call_tool("route_rename_thing", Dict("value" => 1))
    @test parsebody(r)["result"]["content"][1]["text"] == "2"

    # anonymous do-block handler invoked under its derived name
    r = call_tool("post_users_anon", Dict("value" => 4))
    @test parsebody(r)["result"]["content"][1]["text"] == "12"

    # missing required argument
    r = call_tool("route_get_user", Dict())
    @test parsebody(r)["error"]["code"] == -32602
end

### Teardown ##################################################################

terminate()

end
