# Model Context Protocol (MCP)

Oxygen can expose your functions as [Model Context Protocol](https://modelcontextprotocol.io) tools and serve them alongside your regular HTTP API. The implementation targets the stateless `2026-07-28` revision of the protocol and the Streamable HTTP transport.

Once enabled, Oxygen hosts a single `POST /mcp` endpoint that speaks JSON-RPC 2.0 and supports `server/discover`, `tools/list`, and `tools/call`. There is no session handshake: every request carries its own protocol version, client info, and capabilities, so any request can land on any server instance behind a plain load balancer.

## Registering Tools

Tools are registered with the `@tool` macro. The first argument is the tool description, the second declares the parameters, and the final argument is the function itself.

```julia
using Oxygen

@tool "Create a user" Dict(
    :name  => "Full name of the user",
    :email => "Email address"
) function create_user(name::String, email::String)
    return "created $name <$email>"
end
```

The parameter declaration accepts a `Dict` or `NamedTuple` (with `Symbol` keys), or a vector of `Pair`s — the same forms are accepted by route-level `mcp` metadata:

```julia
@tool "Add two integers" (a = "the first addend", b = "the second addend") function add(a::Int, b::Int)
    return a + b
end
```

The parameter names must match the function's signature, and every parameter must be described. A mistyped or extra key, or a parameter left without a description, throws an `ArgumentError`. Parameters without a default are marked as required in the generated JSON Schema, while parameters with defaults are optional. Tool parameters are always exposed under their Julia name; wire-name overrides are only available on route-backed tools via the `names` map (see below).

Metadata may span multiple lines, but the `function` keyword must sit on the same line as the closing metadata token. If you prefer the definition to have its own lines, use the block form:

```julia
@tool "Create a user" Dict(
    :name  => "Full name of the user",
    :email => "Email address"
) begin
    function create_user(name::String, email::String)
        return "created $name <$email>"
    end
end
```

If the description would just repeat the handler's docstring, use the two-argument form and let the docstring supply it:

```julia
"""
Create a user.
"""
@tool Dict(:name => "Full name of the user", :email => "Email address") function create_user(name::String, email::String)
    return "created $name <$email>"
end
```

An undocumented handler registered this way gets an empty description. The same works with `tool(params, func)` for previously defined functions.

For previously defined functions, or when you want an explicit wire name, use the three-argument `tool`:

```julia
function search_users(q::String, limit::Int = 10)
    # ...
end

tool("Search users", Dict(:q => "query", :limit => "max results"), search_users)

# anonymous handler with an explicit wire name (do..end)
tool("Search users", Dict(:q => "query"); name = "search_users") do q::String
    # ...
end
```

Registering two tools with the same wire name throws an error.

## Exposing Routes as Tools

Instead of registering a separate tool, you can expose existing HTTP routes over
MCP by attaching `mcp` metadata to a router or to an individual route. The
metadata is inherited and merged from the router down to the route, so shared
descriptions only need to be written once.

```julia
api = router("/users",
    mcp = (
        description = "User management",
        parameters = Dict(:id => "User ID"),
    ),
)

@post api("/create", mcp = (
    description = "Create a user",
    parameters = Dict(:email => "Email address"),
)) function create_user(req::HTTP.Request, email::String)
    return "created $email"
end

@get api("/{id}", mcp = (description = "Get a user")) function get_user(req::HTTP.Request, id::Int)
    return "user $id"
end
```

The rules are:

- `mcp = true` enables a router or a route with defaults, and a `NamedTuple`
  (or `Dict`) enables it while supplying overrides. `mcp = false` disables the
  group or route. A router-level `false` is authoritative — routes inside it
  cannot opt back in — while a route-level `false` excludes just that route.
- A router's `description` acts as a group prefix: the example above produces
  `"User management: Create a user"` and `"User management: Get a user"`. When a
  route has no description, the handler's docstring is used instead.
- Parameter descriptions merge outer → inner, with route-level values winning.
  In the example `id` is described as `"User ID"` at the router level but `get_user`
  inherits it, while `create_user` adds `email`.
- The tool name defaults to the handler's name, keeping it endpoint-specific. A
  router-level `name` is ignored (it would collide across every route); a route
  can set its own with `name = "..."`. Anonymous handlers fall back to a name
  derived from the HTTP method and path.
- A parameter can be exposed under a different JSON key with a `names` map:

  ```julia
  @post api("/rename", mcp = (
      description = "Rename a user",
      parameters = Dict(:value => "the new name"),
      names = Dict(:value => "new_name"),
  )) function rename_user(req::HTTP.Request, value::String)
      return value
  end
  ```

  The schema advertises `new_name`, and invocations may use either `new_name` or
  the Julia parameter name.

Route-backed tools reuse the route handler, so the leading positional argument
(typically `HTTP.Request`) is injected by the framework and is not part of the
schema. The injected value is the incoming MCP transport request, not a
route-shaped request, so handler logic that reads the route path or query from it
will not see the original endpoint's values. Only plain request handlers
qualify: streaming and websocket routes, and handlers whose leading argument is
not a request, are skipped (`@warn` is emitted when metadata requested a tool that
cannot be built). The leading argument may be left untyped (`function(req, id)`)
or annotated as `HTTP.Request`; both are accepted. As a convenience, a bare
string is treated as the description (`mcp = "Get a user"`), which also makes the
natural single-field form `mcp = (description = "Get a user")` work.

## Registering Prompts

Prompts are user-controlled message templates exposed via `prompts/list` and
`prompts/get`. Register one with `@prompt`; unlike `@tool`, there is no parameter
description dictionary — the handler's own parameters *are* the prompt's arguments.
Parameters without a default are required, and `context`/`request` are injected and
excluded from the argument list.

```julia
@prompt "Report on a city" function city_report(city::String, tone::String = "formal")
    return "Write a $tone report about $city"
end
```

`prompts/list` advertises `city` (required) and `tone` (optional). Return values are
normalized into MCP content blocks:

- `String` → a `text` block (a bare `String` is a single user message)
- `Pair` of `role => content`, or a vector mixing `Pair`s and content, → messages
- `HTTP.Response` → honors its `Content-Type`: text-like media becomes a `text` block,
  while `image/*` and `audio/*` become base64 media blocks
- a pre-shaped content dict (e.g. `Dict("type" => "image", ...)`) passes through

Message roles must be `"user"` or `"assistant"` (the values the spec allows); anything
else is rejected. Tools share the same content-block serialization, so the
`text`/`html`/`json`/`binary`/`file` helpers can be returned from either.

```julia
@prompt "Review code" function code_review(language::String, code::String)
    return ["user" => "Please review this $language code:",
            "user" => "```$language\n$code\n```"]
end
```

For previously defined functions, or an explicit wire name, use `prompt`:

```julia
prompt("Explain a term", explain; name = "explain_term")

prompt("Greets a person"; name = "greet") do name::String
    "Hello $name"
end
```

Registering two prompts with the same wire name throws an error, and the `/mcp`
endpoint is mounted once at least one tool, prompt, or resource is registered.

## Registering Resources

Resources are application-controlled data (files, database schemas, application
state) exposed through `resources/list`, `resources/templates/list`, and
`resources/read`. Register one with `@resource`. A URI with `{var}` placeholders
becomes a resource template, and the handler's own parameters are the template
variables:

```julia
@resource "oxygen://docs/{page}" "Look up a docs page" function docs(page::String)
    return read("docs/$page.md", String)
end
```

Captured values are percent-decoded and coerced to the parameter's declared type,
so `oxygen://users/{id}` with `id::Int` hands the handler an `Int`. This
identifier-safe `{var}` form is the only URI-template syntax supported; anything
else (`{+var}`, `{?var}`, ...) is rejected when the resource is registered.

A URI without placeholders is a static resource, and its handler takes no
arguments beyond the injected `context`/`request`:

```julia
@resource "oxygen://readme" "Project readme" function readme()
    return read("README.md", String)
end
```

The resource `name` defaults to the handler's name. Use the function form for an
explicit name, a display title, a default MIME type, or a size:

```julia
resource("oxygen://config", "Server config", read_config;
         name = "config", title = "Server configuration", mime_type = "application/json")
```

Return values are normalized into `resources/read` contents:

- `String` → a `text` entry (MIME type `text/plain`, or the registered `mime_type`)
- `Vector{UInt8}` → `text` for textual media, base64 `blob` otherwise
- `HTTP.Response` → honors its `Content-Type` the same way
- a vector of the above → multiple contents; a `Pair` may restate the URI per entry
- a pre-shaped content dict (`"uri"` plus `"text"`/`"blob"`), or a whole
  `Dict("contents" => [...])`, passes through

Reading an unknown URI returns the spec's not-found error (`-32002` on the legacy
era, `-32602` on the modern one). A captured value that cannot be coerced into
the parameter's declared type is also `-32602`; handler exceptions become
`-32603`. Once at least one resource or resource template is registered the
`resources` capability is advertised with both `subscribe` and `listChanged` set
to `true`; see [Resource Subscriptions & Change Notifications](#resource-subscriptions--change-notifications).

## The MCP Endpoint

The endpoint becomes available at `POST /mcp` automatically once at least one tool, prompt, or resource has been registered, so `serve()` is all you need. If nothing is registered, the route is not mounted at all. Pass `mcp = false` to `serve` to force-disable the endpoint even when tools, prompts, or resources are registered.

Use the `mcp_path` keyword to mount it somewhere else:

```julia
serve(mcp_path = "/tools/mcp")
```

When the server runs behind a reverse proxy, pass the proxy's path prefix to `serve` with `prefix`. Oxygen strips the prefix before routing, so `mcp_path` stays relative to that prefix and the public URL becomes `prefix + mcp_path`:

```julia
serve(prefix = "/api", mcp_path = "/tools/mcp")
# the endpoint is reached at POST /api/tools/mcp
```

Requests must include the `MCP-Protocol-Version`, `Mcp-Method` headers, plus `Mcp-Name` for `tools/call`, `prompts/get`, and `resources/read` (carrying the request's name or URI). Oxygen validates that the headers match the request body and rejects mismatches with `400 Bad Request`. `DELETE` returns `405`. A `GET` declaring a modern protocol version also returns `405`; a legacy `GET` replies with a JSON health body, or holds the connection open as the legacy server→client notification stream when it declares `Accept: text/event-stream`.

When the autogenerated docs are enabled, an interactive explorer for the endpoint is served at `/docs/mcp` (the docs path followed by `mcp`). It lists the registered tools and prompts and lets you invoke them from the browser, using the same URL the endpoint is reachable at — including any global `prefix` and custom `mcp_path`. Like the rest of the docs pages it disappears when `docs = false`, and it is not mounted when MCP is disabled or no tool, prompt, or resource has been registered.

A quiet call replies with a single JSON object; a streaming `tools/call` replies
with `text/event-stream` when the request carries a `progressToken` and an
`Accept` header that allows SSE (see [Streaming Progress](#streaming-progress)).

```http
POST /mcp HTTP/1.1
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: create_user

{"jsonrpc":"2.0","id":1,"method":"tools/call",
 "params":{"name":"create_user","arguments":{"name":"Alice","email":"alice@example.com"},
 "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",
          "io.modelcontextprotocol/clientCapabilities":{}}}}
```

The server replies with a single JSON object:

```json
{"jsonrpc":"2.0","id":1,
 "result":{"resultType":"complete",
           "content":[{"type":"text","text":"created Alice <alice@example.com>"}],
           "isError":false}}
```

If a handler throws, the error is reported as a tool execution error (`isError: true`) so the model can recover. Requests for unknown tools or with missing required arguments return a JSON-RPC error instead.

## Supported Parameter Types

Parameter schemas are generated from the Julia types in the function signature. Primitive types are mapped directly, enums are exposed as integer enums, and custom structs are inlined into the schema using `$defs`.

```julia
struct Address
    street :: String
    city   :: String
    zip    :: Int
end

@tool "Look up a place" Dict(:address => "the address to look up") function lookup(address::Address)
    return address.city
end
```

JSON values are coerced into the declared types before the handler runs. Nested objects are used to build custom structs, arrays are converted element-wise, and nullable unions (`Union{T, Nothing}`) accept `null`.

## Injecting Context & Requests

Just like route handlers, tool functions can receive the application context and the underlying HTTP request as keyword arguments. Tool functions can also declare `; stream` to receive a streaming handle (see [Streaming Progress](#streaming-progress)). All injected arguments are excluded from the generated schema.

```julia
@tool "Uses the app context" Dict() function whoami(; context)
    return context.username
end

@tool "Uses the request" Dict() function user_agent(; request)
    return request.headers["User-Agent"]
end
```

The application context is the value passed to `serve(context = ...)`.

## Streaming Progress

Long-running tools can report progress while they run instead of staying silent
until the final result. Notifications are delivered on the same request-scoped
SSE response that ends with the result, so the complete `CallToolResult` is
always the last message the client receives.

Wrap the work in `mcp_stream` and publish progress from inside the do-block:

```julia
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
```

The do-block's return value becomes the tool result. Yielded values are
classified automatically:

| Yield | Notification |
| --- | --- |
| `String` | `notifications/progress` with the auto-incremented counter and the string as `message` |
| `Real` | explicit `progress` value (must strictly increase); no message |
| `nothing` | heartbeat: auto-incremented, no message |
| `progress(current, total; message=...)` | explicit value, optional `total` and `message` |
| anything else | JSON-encoded into the `message` |

Auto-numbering starts at 1 and is monotonic per request, so loop counters are
optional:

```julia
put!(stream, "imported $url")   # progress 1, 2, 3, ...
```

There is no separate logging notification surface; yield a dict or tuple to
attach your own structured payload to a progress `message` and let the client
parse it.

Handlers that cannot wrap their work in a do-block can take the injected
`stream` handle instead and call `emit(stream, value)`:

```julia
@tool "Import a catalog" Dict(:urls => "catalog URLs") function import_catalog(urls::Vector{String}; stream)
    for url in urls
        emit(stream, "imported $url")
    end
    return "Imported $(length(urls)) records"
end
```

Clients opt in with `_meta.progressToken` (a string or integer) and an `Accept`
header that allows `text/event-stream`. When the request includes a token, the
first notification upgrades the POST response to SSE:

```text
event: message
data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"tok-1","progress":1,"message":"imported a.json"}}

event: message
data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"tok-1","progress":2,"message":"imported b.json"}}

event: message
data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Imported 2 records"}],"isError":false}}
```

Without a token (or when the client does not accept SSE), notifications are
dropped and the call returns exactly the JSON response it would have returned
without streaming — a call never fails because the client did not opt in. A
tool that never emits also stays `application/json`. A tool error after the
first notification ends the SSE stream with an `isError: true` result; an error
before it returns the JSON error result.

The per-request event channel is bounded (64 events), so a slow client
backpressures the producer instead of buffering without limit. When the client
disconnects, the channel is closed and a producer blocked in `put!` unwinds;
cooperative loops can call `check_cancelled(stream)` between steps to stop
promptly, and `emit(stream, ...)` throws once the request has been cancelled.

Streaming works on both the modern and legacy POST paths. Over stdio there is
no SSE: progress notifications are written as newline-delimited JSON-RPC
messages, interleaved with the eventual response. Only tool handlers can
stream; route-backed tools invoke the route's own request and never emit.

`mcp_stream`, `emit`, `progress`, and `check_cancelled` are exported by Oxygen.

## Resource Subscriptions & Change Notifications

Clients can subscribe to changes instead of polling. Publish a change from
anywhere in your app with the exported helpers:

```julia
notify_resource_updated("oxygen://readme")  # contents of one resource changed
notify_resources_changed()                  # resources/list changed
notify_tools_changed()                      # tools/list changed
notify_prompts_changed()                    # prompts/list changed
```

Each returns the number of subscriber queues the notification was enqueued into
(a queue that dropped the value does not count). The
`notify_*_changed` helpers are also called automatically whenever a tool,
prompt, or resource is registered, so the advertised `listChanged` capability
is always truthful. A notification published inside a tool handler goes to the
subscribers, never onto that call's own progress stream:

```julia
const PLACES = Dict("NYC" => "40.7,-74.0")

@resource "maps://places" "Known places" function places_resource()
    return PLACES
end

@tool "Add a place" Dict(:name => "place name") function add_place(name::String)
    PLACES[name] = "0.0,0.0"
    notify_resource_updated("maps://places")
    return "added $name"
end
```

### Modern: `subscriptions/listen`

A modern (2026-07-28) client opens a long-lived stream by POSTing
`subscriptions/listen` with a filter and `Accept: text/event-stream`:

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "subscriptions/listen",
  "params": {
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {}
    },
    "notifications": {
      "resourcesListChanged": true,
      "resourceSubscriptions": ["maps://places"]
    }
  }
}
```

The response is an SSE stream whose first frame is always
`notifications/subscriptions/acknowledged`, carrying the honored subset of the
filter (types the server cannot deliver are omitted, so the ack is the honest
source of what will arrive). Every message, including the closing result on
graceful shutdown, carries the listen request id as
`params._meta["io.modelcontextprotocol/subscriptionId"]` — that id is how
clients demultiplex streams on stdio.

Filtering is per stream: the server never sends a type the client did not
request. Each filter may watch at most 256 resource URIs, and each server
supports at most 64 concurrent listen streams; a full backlog (256 frames)
closes the stream (already-buffered frames are still drained). The modern
stream is SSE-only: a request without `Accept: text/event-stream` is rejected
with `-32600`.

Over stdio, a listen stream is cancelled by sending `notifications/cancelled`
with `params.requestId` set to the listen request id; over HTTP it is cancelled
by closing the connection.

### Legacy: `resources/subscribe`

Legacy clients call `resources/subscribe` with a URI (and
`resources/unsubscribe` to stop):

```json
{"jsonrpc": "2.0", "id": 1, "method": "resources/subscribe", "params": {"uri": "maps://places"}}
```

Both are idempotent and return an empty result. Updates arrive as
`notifications/resources/updated` on the legacy server→client channel: the GET
`text/event-stream` connection over HTTP, or `stdout` over stdio. Legacy
delivery is single-session — one subscription set and one notification channel
per server — and only starts after a completed `initialize` handshake, so
legacy HTTP notifications reach a single GET listener.

## stdio Transport

MCP clients that launch the server as a subprocess can talk over standard streams instead of HTTP. Pass `stdio = true` to `serve` and Oxygen will read newline-delimited JSON-RPC messages from `stdin` and write responses to `stdout`, in addition to the HTTP endpoint. Passing `mcp = false` disables the stdio transport as well.

```julia
serve(stdio = true)
```

Oxygen writes its own status output (the startup banner, access logs, task and cron messages, deprecation warnings) to `stderr`, leaving `stdout` reserved for protocol messages. Avoid writing to `stdout` from your tool handlers. Closing `stdin` is treated as the graceful shutdown signal and terminates the server. The stdio transport has no header layer: the protocol version and client capabilities are read from `_meta` on each message, and any registered tool can be invoked.

## Isolation

Tool registration is scoped to the application instance. Each `@oxidize` module and each `instance()` has its own registry, so tools never leak between applications. When the server is terminated and `resetstate()` is called interactively, the registry is cleared just like routes.
