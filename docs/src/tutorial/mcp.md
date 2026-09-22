# Model Context Protocol (MCP)

Oxygen can expose your functions as [Model Context Protocol](https://modelcontextprotocol.io) tools and serve them alongside your regular HTTP API. The implementation targets the stateless `2026-07-28` revision of the protocol and the Streamable HTTP transport.

Once enabled, Oxygen hosts a single `POST /mcp` endpoint that speaks JSON-RPC 2.0 and supports `server/discover`, `tools/list`, and `tools/call`. There is no session handshake: every request carries its own protocol version, client info, and capabilities, so any request can land on any server instance behind a plain load balancer.

## Registering Tools

Tools are registered with the `@tool` macro. The first argument is the tool description, the second is a `Dict` of parameter descriptions, and the final argument is the function itself.

```julia
using Oxygen

@tool "Create a user" Dict(
    :name  => "Full name of the user",
    :email => "Email address"
) function create_user(name::String, email::String)
    return "created $name <$email>"
end
```

The parameter names must match the function's signature. Parameters without a default are marked as required in the generated JSON Schema, while parameters with defaults are optional.

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

For previously defined functions, or when you want an explicit wire name, use `tool`:

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
endpoint is mounted once at least one tool *or* prompt is registered.

## The MCP Endpoint

The endpoint becomes available at `POST /mcp` automatically once at least one tool or prompt has been registered, so `serve()` is all you need. If nothing is registered, the route is not mounted at all.

Use the `mcp_path` keyword to mount it somewhere else:

```julia
serve(mcp_path = "/tools/mcp")
```

When the server runs behind a reverse proxy, pass the proxy's path prefix to `serve` with `prefix`. Oxygen strips the prefix before routing, so `mcp_path` stays relative to that prefix and the public URL becomes `prefix + mcp_path`:

```julia
serve(prefix = "/api", mcp_path = "/tools/mcp")
# the endpoint is reached at POST /api/tools/mcp
```

Requests must include the `MCP-Protocol-Version`, `Mcp-Method` headers, plus `Mcp-Name` for `tools/call`. Oxygen validates that the headers match the request body and rejects mismatches with `400 Bad Request`. `GET` and `DELETE` on the endpoint return `405`.

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
           "structuredContent":"created Alice <alice@example.com>",
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

Just like route handlers, tool functions can receive the application context and the underlying HTTP request as keyword arguments. Both are excluded from the generated schema.

```julia
@tool "Uses the app context" Dict() function whoami(; context)
    return context.username
end

@tool "Uses the request" Dict() function user_agent(; request)
    return request.headers["User-Agent"]
end
```

The application context is the value passed to `serve(context = ...)`.

## stdio Transport

MCP clients that launch the server as a subprocess can talk over standard streams instead of HTTP. Pass `stdio = true` to `serve` and Oxygen will read newline-delimited JSON-RPC messages from `stdin` and write responses to `stdout`, in addition to the HTTP endpoint.

```julia
serve(stdio = true)
```

Oxygen writes its own status output (the startup banner, access logs, task and cron messages, deprecation warnings) to `stderr`, leaving `stdout` reserved for protocol messages. Avoid writing to `stdout` from your tool handlers. Closing `stdin` is treated as the graceful shutdown signal and terminates the server. The stdio transport has no header layer: the protocol version and client capabilities are read from `_meta` on each message, and any registered tool can be invoked.

## Isolation

Tool registration is scoped to the application instance. Each `@oxidize` module and each `instance()` has its own registry, so tools never leak between applications. When the server is terminated and `resetstate()` is called interactively, the registry is cleared just like routes.
