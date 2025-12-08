# Oxygen.jl

<!-- START HTML -->
<div>
  </br>
  <p align="center"><img src="oxygen.png" width="20%"></p>
  <p align="center">
    <strong>A breath of fresh air for programming web apps in Julia.</strong>
  </p>
  <p align="center">
    <a href='https://juliahub.com/ui/Packages/General/Oxygen'><img src='https://juliahub.com/docs/General/Oxygen/stable/version.svg' alt='Version' /></a>
    <a href='https://oxygenframework.github.io/Oxygen.jl/stable/'><img src='https://img.shields.io/badge/docs-stable-blue.svg' alt='documentation stable' /></a>
    <a href='https://github.com/OxygenFramework/Oxygen.jl/actions/workflows/ci.yml'><img src='https://github.com/OxygenFramework/Oxygen.jl/actions/workflows/ci.yml/badge.svg' alt='Build Status' /></a>
    <a href='https://coveralls.io/github/OxygenFramework/Oxygen.jl?branch=master'><img src='https://coveralls.io/repos/github/OxygenFramework/Oxygen.jl/badge.svg?branch=master' alt='Coverage Status' /></a>
    <!-- <a href='https://codecov.io/gh/OxygenFramework/Oxygen.jl'><img src='https://codecov.io/gh/OxygenFramework/Oxygen.jl/branch/master/graph/badge.svg' alt='Coverage Status' /></a> -->
  </p>
</div>
<!-- END HTML -->

## About
Oxygen is a micro-framework built on top of the HTTP.jl library. 
Breathe easy knowing you can quickly spin up a web server with abstractions you're already familiar with.

## Contact

Need Help? Feel free to reach out on our social media channels.

[![Chat on Discord](https://img.shields.io/badge/chat-Discord-7289DA?logo=discord)](https://discord.gg/g5dmzRkdAR) 
[![Discuss on GitHub](https://img.shields.io/badge/discussions-GitHub-333333?logo=github)](https://github.com/OxygenFramework/Oxygen.jl/discussions)

## Features

- Straightforward routing
- Real-time Metrics Dashboard
- Auto-generated swagger documentation
- Out-of-the-box JSON serialization & deserialization (customizable)
- Type definition support for path parameters
- Request Extractors
- Application Context
- Multiple Instance Support
- Multithreading support
- Websockets, Streaming, and Server-Sent Events
- Cron Scheduling (on endpoints & functions)
- Middleware chaining (at the application, router, and route levels)
- Prebuilt Middleware - RateLimiter, Cors, BearerAuth
- Static & Dynamic file hosting
- Hot reloads with Revise.jl
- Templating Support
- Plotting Support
- Protocol Buffer Support
- Route tagging
- Repeat tasks

## Installation

```julia
pkg> add Oxygen
```

## Minimalistic Example

Create a web-server with very few lines of code
```julia
using Oxygen
using HTTP

@get "/greet" function(req::HTTP.Request)
    return "hello world!"
end

# start the web server
serve()
```
## Handlers

Handlers are used to connect your code to the server in a clean & straightforward way. 
They assign a url to a function and invoke the function when an incoming request matches that url.


- Handlers can be imported from other modules and distributed across multiple files for better organization and modularity
- All handlers have equivalent macro & function implementations and support `do..end` block syntax
- The type of first argument is used to identify what kind of handler is being registered
- This package assumes it's a `Request` handler by default when no type information is provided


There are 3 types of supported handlers:

- `Request` Handlers
- `Stream` Handlers
- `Websocket` Handlers

```julia
using HTTP
using Oxygen

# Request Handler
@get "/" function(req::HTTP.Request)
    ...
end

# Stream Handler
@stream "/stream" function(stream::HTTP.Stream)
    ...
end

# Websocket Handler
@websocket "/ws" function(ws::HTTP.WebSocket)
    ...
end
```

They are just functions which means there are many ways that they can be expressed and defined. Below is an example of several different ways you can express and assign a `Request` handler.
```julia
@get "/greet" function()
    "hello world!"
end

@get("/gruessen") do 
    "Hallo Welt!"
end

@get "/saluer" () -> begin
    "Bonjour le monde!"
end

@get "/saludar" () -> "¡Hola Mundo!"
@get "/salutare" f() = "ciao mondo!"

# This function can be declared in another module
function subtract(req, a::Float64, b::Float64)
  return a - b
end

# register foreign request handlers like this
@get "/subtract/{a}/{b}" subtract
```

<details>
    <summary><b>More Handler Docs</b></summary>
    
### Request Handlers
Request handlers are used to handle HTTP requests. They are defined using macros or their function equivalents, and accept a `HTTP.Request` object as the first argument. These handlers support both function and do-block syntax.

- The default Handler when no type information is provided
- Routing Macros: `@get`, `@post`, `@put`, `@patch`, `@delete`, `@route`
- Routing Functions: `get()`, `post()`, `put()`, `patch()`, `delete()`, `route()`

### Stream Handlers
Stream handlers are used to stream data. They are defined using the `@stream` macro or the `stream()` function and accept a `HTTP.Stream` object as the first argument. These handlers support both function and do-block syntax.

- `@stream` and `stream()` don't require a type definition on the first argument, they assume it's a stream.
- `Stream` handlers can be assigned with standard routing macros & functions: `@get`, `@post`, etc
- You need to explicitly include the type definition so Oxygen can identify this as a `Stream` handler

### Websocket Handlers
Websocket handlers are used to handle websocket connections. They are defined using the `@websocket` macro or the `websocket()` function and accept a `HTTP.WebSocket` object as the first argument. These handlers support both function and do-block syntax.

- `@websocket` and `websocket()` don't require a type definition on the first argument, they assume it's a websocket.
- `Websocket` handlers can also be assigned with the `@get` macro or `get()` function, because the websocket protocol requires a `GET` request to initiate the handshake. 
- You need to explicitly include the type definition so Oxygen can identify this as a `Websocket` handler

</details>


## Routing Macro & Function Syntax

There are two primary ways to register your request handlers: the standard routing macros or the routing functions which utilize the do-block syntax. 

For each routing macro, we now have a an equivalent routing function

```julia
@get    -> get()
@post   -> post()
@put    -> put()
@patch  -> patch()
@delete -> delete()
@route  -> route()
```

The only practical difference between the two is that the routing macros are called during the precompilation
stage, whereas the routing functions are only called when invoked. (The routing macros call the routing functions under the hood)

```julia
# Routing Macro syntax
@get "/add/{x}/{y}" function(request::HTTP.Request, x::Int, y::Int)
    x + y
end

# Routing Function syntax
get("/add/{x}/{y}") do request::HTTP.Request, x::Int, y::Int
    x + y
end
```

## Render Functions

Oxygen, by default, automatically identifies the Content-Type of the return value from a request handler when building a Response.
This default functionality is quite useful, but it does have an impact on performance. In situations where the return type is known,
It's recommended to use one of the pre-existing render functions to speed things up.

Here's a list of the currently supported render functions:
`html`, `text`, `json`, `file`, `xml`, `js`, `css`, `binary`

Below is an example of how to use these functions:

```julia
using Oxygen 

get("/html") do 
    html("<h1>Hello World</h1>")
end

get("/text") do 
    text("Hello World")
end

get("/json") do 
    json(Dict("message" => "Hello World"))
end

serve()
```

In most cases, these functions accept plain strings as inputs. The only exceptions are the `binary` function, which accepts a `Vector{UInt8}`, and the `json` function which accepts any serializable type. 
- Each render function accepts a status and custom headers.
- The Content-Type and Content-Length headers are automatically set by these render functions


## Path parameters

Path parameters are declared with braces and are passed directly to your request handler. 
```julia
using Oxygen

# use path params without type definitions (defaults to Strings)
@get "/add/{a}/{b}" function(req, a, b)
    return parse(Float64, a) + parse(Float64, b)
end

# use path params with type definitions (they are automatically converted)
@get "/multiply/{a}/{b}" function(req, a::Float64, b::Float64)
    return a * b
end

# The order of the parameters doesn't matter (just the name matters)
@get "/subtract/{a}/{b}" function(req, b::Int64, a::Int64)
    return a - b
end

# start the web server
serve()
```

## Query parameters


Query parameters can be declared directly inside of your handlers signature. Any parameter that isn't mentioned inside the route path is assumed to be a query parameter.

- If a default value is not provided, it's assumed to be a required parameter

```julia
@get "/query" function(req::HTTP.Request, a::Int, message::String="hello world")
    return (a, message)
end
```

Alternatively, you can use the `queryparams()` function to extract the raw values from the url as a dictionary. 

```julia
@get "/query" function(req::HTTP.Request)
    return queryparams(req)
end
```

## HTML Forms

Use the `formdata()` function to extract and parse the form data from the body of a request. This function returns a dictionary of key-value pairs from the form
```julia
using Oxygen

# Setup a basic form
@get "/" function()
    html("""
    <form action="/form" method="post">
        <label for="firstname">First name:</label><br>
        <input type="text" id="firstname" name="firstname"><br>
        <label for="lastname">Last name:</label><br>
        <input type="text" id="lastname" name="lastname"><br><br>
        <input type="submit" value="Submit">
    </form>
    """)
end

# Parse the form data and return it
@post "/form" function(req)
    data = formdata(req)
    return data
end

serve()
```

## Return JSON

All objects are automatically deserialized into JSON using the JSON3 library

```julia
using Oxygen
using HTTP

@get "/data" function(req::HTTP.Request)
    return Dict("message" => "hello!", "value" => 99.3)
end

# start the web server
serve()
```

## Deserialize & Serialize custom structs
Oxygen provides out-of-the-box serialization & deserialization for all objects and structs using the JSON.jl package

```julia
using Oxygen
using HTTP

struct Animal
    id::Int
    type::String
    name::String
end

@get "/get" function(req::HTTP.Request)
    # serialize struct into JSON automatically
    return Animal(1, "cat", "whiskers")
end

@post "/echo" function(req::HTTP.Request)
    # deserialize JSON from the request body into an Animal struct
    animal = json(req, Animal)
    # serialize struct back into JSON automatically
    return animal
end

# start the web server
serve()
```

## Extractors

Oxygen comes with several built-in extractors designed to reduce the amount of boilerplate required to serialize inputs to your handler functions. By simply defining a struct and specifying the data source, these extractors streamline the process of data ingestion & validation through a uniform api.

- The serialized data is accessible through the `payload` property
- Can be used alongside other parameters and extractors
- Default values can be assigned when defined with the `@kwdef` macro
- Includes both global and local validators
- Struct definitions can be deeply nested

Supported Extractors:

- `Path` - extracts from path parameters
- `Query` - extracts from query parameters, 
- `Header` - extracts from request headers
- `Form` - extracts form data from the request body
- `Body` - serializes the entire request body to a given type (String, Float64, etc..)
- `ProtoBuffer` - extracts the `ProtoBuf` message from the request body (available through a package extension)
- `Json` - extracts json from the request body
- `JsonFragment` - extracts a "fragment" of the json body using the parameter name to identify and extract the corresponding top-level key


#### Using Extractors & Parameters

In this example we show that the `Path` extractor can be used alongside regular path parameters. This Also works with regular query parameters and the `Query` extractor.

```julia
struct Add
    b::Int
    c::Int
end

@get "/add/{a}/{b}/{c}" function(req, a::Int, pathparams::Path{Add})
    add = pathparams.payload # access the serialized payload
    return a + add.b + add.c
end
```

#### Default Values

Default values can be setup with structs using the `@kwdef` macro.

```julia
@kwdef struct Pet
    name::String
    age::Int = 10
end

@post "/pet" function(req, params::Json{Pet})
    return params.payload # access the serialized payload
end
```

#### Nullable Types
You can indicate that a field may be null by declaring it as a Union type with `Nothing`.
> **Note:** While the serializer can handle type `::Union{T,Missing}` it will fail if a default value of `missing` provided. Instead use `::Union{T,Nothing} = nothing`.

```julia
@kwdef struct Pet
    name::Union{String,Nothing} # Valid
    surname::Union{String,Nothing} = nothing # Valid
    eyecolor::Union{ColorStruct, Missing} # Valid 
    coatcolor::Union{ColorStruct,Missing} = missing # Invalid: no schema will be generated for `Pet` 
    age::Int = 10
end

```

#### Validation

On top of serializing incoming data, you can also define your own validation rules by using the `validate` function. In the example below we show how to use both `global` and `local` validators in your code.

- Validators are completely optional
- During the validation phase, oxygen will call the `global` validator before running a `local` validator.

```julia
import Oxygen: validate

struct Person
    name::String
    age::Int
end

# Define a global validator 
validate(p::Person) = p.age >= 0

# Only the global validator is ran here
@post "/person" function(req, newperson::Json{Person})
    return newperson.payload
end

# In this case, both global and local validators are ran (this also makes sure the person is age 21+)
# You can also use this sytnax instead: Json(Person, p -> p.age >= 21)
@post "/adult" function(req, newperson = Json{Person}(p -> p.age >= 21))
    return newperson.payload
end
```

## Application Context

Most applications at some point will need to rely on some shared global state across the codebase. 
This usually comes in the form of a shared database connection pool or some other in memory store. 
Oxygen provides a `context` argument which acts as a free spot for developers to store any objects that 
should be available throughout the lifetime of an application.

There are three primary ways to get access to your application context
- Injected into any request handler using the `Context` struct.
- The `context` keyword argument in a function handler
- Through the `context()` function 

*There are no built-in data race protections*, but this is intentional. Not all applications have the same requirements, 
so it's up to the developer to decide how to best handle this. For those who need to share mutable state across multiple
threads I'd recommend looking into using `Actors`, `Channels`, or `ReentrantLocks` to handle this quickly.

Below is a simplified example where we store a `Person` as the application context to show how things are 
connected and shared.

```julia
using Oxygen

struct Person
    name::String
end

# The ctx argument here is injected through the Context class
@get "/ctx-injection" function(req, ctx::Context{Person})
    person :: Person = ctx.payload # access the underlying value
    return "Hello $(person.name)!"
end

# Access the context through the 'context' keyword argument 
@get "/ctx-kwarg" function(req; context)
    person :: Person = context 
    return "Hello $(person.name)!"
end

# Access context through the 'context()' function
@get "/ctx-function" function(req)
    person :: Person = context()
    return "Hello $(person.name)!"
end

# This represents the application context shared between all handlers
person = Person("John")

# Here is how we set the application context in our server
serve(context=person)
```

## Interpolating variables into endpoints

You can interpolate variables directly into the paths, which makes dynamically registering routes a breeze 

(Thanks to @anandijain for the idea)
```julia
using Oxygen

operations = Dict("add" => +, "multiply" => *)
for (pathname, operator) in operations
    @get "/$pathname/{a}/{b}" function (req, a::Float64, b::Float64)
        return operator(a, b)
    end
end

# start the web server
serve()
```
## Routers

The `router()` function is an HOF (higher order function) that allows you to reuse the same path prefix & properties across multiple endpoints. This is helpful when your api starts to grow and you want to keep your path operations organized.

Below are the arguments the `router()` function can take:
```julia
router(prefix::String; tags::Vector, middleware::Vector, interval::Real, cron::String)
```
- `tags` - are used to organize endpoints in the autogenerated docs
- `middleware` - is used to setup router & route-specific middleware
- `interval` - is used to support repeat actions (*calling a request handler on a set interval in seconds*)
- `cron` - is used to specify a cron expression that determines when to call the request handler.

```julia
using Oxygen

# Any routes that use this router will be automatically grouped 
# under the 'math' tag in the autogenerated documenation
math = router("/math", tags=["math"])

# You can also assign route specific tags
@get math("/multiply/{a}/{b}", tags=["multiplication"]) function(req, a::Float64, b::Float64)
    return a * b
end

@get math("/divide/{a}/{b}") function(req, a::Float64, b::Float64)
    return a / b
end

serve()
```

## Cron Scheduling 

Oxygen comes with a built-in cron scheduling system that allows you to call endpoints and functions automatically when the cron expression matches the current time.

When a job is scheduled, a new task is created and runs in the background. Each task uses its given cron expression and the current time to determine how long it needs to sleep before it can execute.

The cron parser in Oxygen is based on the same specifications as the one used in Spring. You can find more information about this on the [Spring Cron Expressions](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/support/CronExpression.html) page.

### Cron Expression Syntax
The following is a breakdown of what each parameter in our cron expression represents. While our specification closely resembles the one defined by Spring, it's not an exact 1-to-1 match.
```
The string has six single space-separated time and date fields:

 ┌───────────── second (0-59)
 │ ┌───────────── minute (0 - 59)
 │ │ ┌───────────── hour (0 - 23)
 │ │ │ ┌───────────── day of the month (1 - 31)
 │ │ │ │ ┌───────────── month (1 - 12) (or JAN-DEC)
 │ │ │ │ │ ┌───────────── day of the week (1 - 7)
 │ │ │ │ │ │          (Monday is 1, Tue is 2... and Sunday is 7)
 │ │ │ │ │ │
 * * * * * *
```
Partial expressions are also supported, which means that subsequent expressions can be left out (they are defaulted to `'*'`). 

```julia
# In this example we see only the `seconds` part of the expression is defined. 
# This means that all following expressions are automatically defaulted to '*' expressions
@cron "*/2" function()
    println("runs every 2 seconds")
end
```

### Scheduling Endpoints

The `router()` function has a keyword argument called `cron`, which accepts a cron expression that determines when an endpoint is called. Just like the other keyword arguments, it can be reused by endpoints that share routers or be overridden by inherited endpoints.

```julia
# execute at 8, 9 and 10 o'clock of every day.
@get router("/cron-example", cron="0 0 8-10 * * *") function(req)
    println("here")
end

# execute this endpoint every 5 seconds (whenever current_seconds % 5 == 0)
every5 = router("/cron", cron="*/5")

# this endpoint inherits the cron expression
@get every5("/first") function(req)
    println("first")
end

# Now this endpoint executes every 2 seconds ( whenever current_seconds % 2 == 0 ) instead of every 5
@get every5("/second", cron="*/2") function(req)
    println("second")
end
```

### Scheduling Functions

In addition to scheduling endpoints, you can also use the new `@cron` macro to schedule functions. This is useful if you want to run code at specific times without making it visible or callable in the API.

```julia
@cron "*/2" function()
    println("runs every 2 seconds")
end

@cron "0 0/30 8-10 * * *" function()
  println("runs at 8:00, 8:30, 9:00, 9:30, 10:00 and 10:30 every day")
end
```

### Starting & Stopping Cron Jobs

When you run `serve()` or `serveparallel()`, all registered cron jobs are automatically started. If the server is stopped or killed, all running jobs will also be terminated. You can stop the server and all repeat tasks and cron jobs by calling the `terminate()` function or manually killing the server with `ctrl+C`.

In addition, Oxygen provides utility functions to manually start and stop cron jobs: `startcronjobs()` and `stopcronjobs()`. These functions can be used outside of a web server as well.

## Repeat Tasks

Repeat tasks provide a simple api to run a function on a set interval. 

There are two ways to register repeat tasks: 
- Through the `interval` parameter in a `router()`
- Using the `@repeat` macro


**It's important to note that request handlers that use this property can't define additional function parameters outside of the default `HTTP.Request` parameter.**

In the example below, the `/repeat/hello` endpoint is called every 0.5 seconds and `"hello"` is printed to the console each time.

The `router()` function has an `interval` parameter which is used to call
a request handler on a set interval (in seconds). 

```julia
using Oxygen

taskrouter = router("/repeat", interval=0.5, tags=["repeat"])

@get taskrouter("/hello") function()
    println("hello")
end

# you can override properties by setting route specific values 
@get taskrouter("/bonjour", interval=1.5) function()
    println("bonjour")
end

serve()
```

Below is an example of how to register a repeat task outside of the router
```julia
@repeat 1.5 function()
    println("runs every 1.5 seconds")
end

# you can also "name" a repeat task 
@repeat 5 "every-five" function()
    println("runs every 5 seconds")
end
```

When the server is ran, all tasks are started automatically. But the module also provides utilities to have more fine-grained control over the running tasks using the following functions: `starttasks()`, `stoptasks()`, and `cleartasks()`

## Hot reloads with Revise

Oxygen can integrate with Revise to provide hot reloads, speeding up development. Since Revise recommends keeping all code to be revised in a package, you first need to move to this type of a layout.

[First make sure your `Project.toml` has the required fields such as `name` to work on a package rather than a project.](https://pkgdocs.julialang.org/v1/toml-files/)

Next, write the main code for you routes in a module `src/MyModule.jl`:

```
module MyModule

using Oxygen; @oxidize

@get "/greet" function(req::HTTP.Request)
    return "hello world!"
end

end
```

Then you can make a `debug.jl` entrypoint script:

```
using Revise
using Oxygen
using MyModule

MyModule.serve(revise=:eager)
```

The `revise` option can also be set to `:lazy`, in which case revisions will always be left to just before a request is served, rather than being attempted eagerly when source files change on disk.

Note that you should run another entrypoint script without Revise in production.

## Multiple Instances

In some advanced scenarios, you might need to spin up multiple web severs within the same module on different ports. Oxygen provides both a static and dynamic way to create multiple instances of a web server.

As a general rule of thumb, if you know how many instances you need ahead of time it's best to go with the static approach.

### Static: multiple instance's with `@oxidize` 

Oxygen provides a new macro which makes it possible to setup and run multiple instances. It generates methods and binds them to a new internal state for the current module. 

In the example below, two simple servers are defined within modules A and B and are started in the parent module. Both modules contain all of the functions exported from Oxygen which can be called directly as shown below.

```julia
module A
    using Oxygen; @oxidize

    get("/") do
        text("server A")
    end
end

module B
    using Oxygen; @oxidize

    get("/") do
        text("server B")
    end
end

try 
    # start both instances
    A.serve(port=8001, async=true)
    B.serve(port=8002, async=false)
finally
    # shut down if we `Ctrl+C`
    A.terminate()
    B.terminate()
end
```

### Dynamic: multiple instance's with `instance()` 

The `instance` function helps you create a completely independent instance of an Oxygen web server at runtime. It works by dynamically creating a julia module at runtime and loading the Oxygen code within it.

All of the same methods from Oxygen are available under the named instance. In the example below we can use the `get`, and `serve` by simply using dot syntax on the `app1` variable to access the underlying methods.


```julia
using Oxygen

######### Setup the first app #########

app1 = instance()

app1.get("/") do
    text("server A")
end

######### Setup the second app #########

app2 = instance()

app2.get("/") do
    text("server B")
end

######### Start both instances #########

try 
    # start both servers together
    app1.serve(port=8001, async=true)
    app2.serve(port=8002)
finally
    # clean it up
    app1.terminate()
    app2.terminate()
end
```

## Multithreading & Parallelism

For scenarios where you need to handle higher amounts of traffic, you can run Oxygen in a 
multithreaded mode. In order to utilize this mode, julia must have more than 1 thread to work with. You can start a julia session with 4 threads using the command below
```shell 
julia --threads 4
```

``serveparallel()`` Starts the webserver in streaming mode and handles requests in a cooperative multitasking approach. This function uses `Threads.@spawn` to schedule a new task on any available thread. Meanwhile, @async is used inside this task when calling each request handler. This allows the task to yield during I/O operations.

```julia
using Oxygen
using Base.Threads

x = Atomic{Int64}(0);

@get "/show" function()
    return x
end

@get "/increment" function()
    atomic_add!(x, 1)
    return x
end

# start the web server in parallel mode
serveparallel()
```

## Protocol Buffers

Oxygen includes an extension for the [ProtoBuf.jl](https://github.com/JuliaIO/ProtoBuf.jl) package. This extension provides a `protobuf()` function, simplifying the process of working with Protocol Buffers in the context of web server. For a better understanding of this package, please refer to its official documentation.



This function has overloads for the following scenarios:
- Decoding a protobuf message from the body of an HTTP request.
- Encoding a protobuf message into the body of an HTTP request.
- Encoding a protobuf message into the body of an HTTP response.


```julia
using HTTP
using ProtoBuf
using Oxygen

# The generated classes need to be created ahead of time (check the protobufs)
include("people_pb.jl");
using .people_pb: People, Person

# Decode a Protocol Buffer Message 
@post "/count" function(req::HTTP.Request)
    # decode the request body into a People object
    message = protobuf(req, People)
    # count the number of Person objects
    return length(message.people)
end

# Encode & Return Protocol Buffer message
@get "/get" function()
    message = People([
        Person("John Doe", 20),
        Person("Alice", 30),
        Person("Bob", 35)
    ])
    # seralize the object inside the body of a HTTP.Response
    return protobuf(message)
end
```

The following is an example of a schema that was used to create the necessary Julia bindings. These bindings allow for the encoding and decoding of messages in the above example.
```protobuf
syntax = "proto3";
message Person {
    string name = 1;
    sint32 age = 2;
}
message People {
    repeated Person people = 1;
}
```


## Plotting

Oxygen is equipped with several package extensions that enhance its plotting capabilities. These extensions make it easy to return plots directly from request handlers. All operations are performed in-memory using an IOBuffer and return a `HTTP.Response`

Supported Packages and their helper utils:

- CairoMakie.jl: `png`, `svg`, `pdf`, `html`
- WGLMakie.jl: `html`
- Bonito.jl: `html`

#### CairoMakie.jl
```julia
using CairoMakie: heatmap
using Oxygen

@get "/cairo" function()
    fig, ax, pl = heatmap(rand(50, 50))
    png(fig)
end

serve()
```

#### WGLMakie.jl
```julia
using Bonito
using WGLMakie: heatmap
using Oxygen
using Oxygen: html # Bonito also exports html

@get "/wgl" function()
    fig = heatmap(rand(50, 50))
    html(fig)
end

serve()
```

#### Bonito.jl
```julia
using Bonito
using WGLMakie: heatmap
using Oxygen
using Oxygen: html # Bonito also exports html

@get "/bonito" function()
    app = App() do
        return DOM.div(
            DOM.h1("Random 50x50 Heatmap"), 
            DOM.div(heatmap(rand(50, 50)))
        )
    end
    return html(app)
end

serve()
```


## Templating

Rather than building an internal engine for templating or adding additional dependencies, Oxygen 
provides two package extensions to support `Mustache.jl` and `OteraEngine.jl` templates.

Oxygen provides a simple wrapper api around both packages that makes it easy to render templates from strings,
templates, and files. This wrapper api returns a `render` function which accepts a dictionary of inputs to fill out the
template.

In all scenarios, the rendered template is returned inside a HTTP.Response object ready to get served by the api.
By default, the mime types are auto-detected either by looking at the content of the template or the extension name on the file.
If you know the mime type you can pass it directly through the `mime_type` keyword argument to skip the detection process.

### Mustache Templating
Please take a look at the [Mustache.jl](https://jverzani.github.io/Mustache.jl/dev/) documentation to learn the full capabilities of the package

Example 1: Rendering a Mustache Template from a File

```julia
using Mustache
using Oxygen

# Load the Mustache template from a file and create a render function
render = mustache("./templates/greeting.txt", from_file=true)

@get "/mustache/file" function()
    data = Dict("name" => "Chris")
    return render(data)  # This will return an HTML.Response with the rendered template
end
```

Example 2: Specifying MIME Type for a plain string Mustache Template
```julia
using Mustache
using Oxygen

# Define a Mustache template (both plain strings and mustache templates are supported)
template_str = "Hello, {{name}}!"

# Create a render function, specifying the MIME type as text/plain
render = mustache(template_str, mime_type="text/plain") # mime_type keyword arg is optional 

@get "/plain/text" function()
    data = Dict("name" => "Chris")
    return render(data)  # This will return a plain text response with the rendered template
end
```

### Otera Templating
Please take a look at the [OteraEngine.jl](https://mommawatasu.github.io/OteraEngine.jl/dev/tutorial/#API) documentation to learn the full capabilities of the package

Example 1: Rendering an Otera Template with Logic and Loops

```julia
using OteraEngine
using Oxygen

# Define an Otera template
template_str = """
<html>
    <head><title>{{ title }}</title></head>
    <body>
        {% for name in names %}
        Hello {{ name }}<br>
        {% end %}
    </body>
</html>
"""

# Create a render function for the Otera template
render = otera(template_str)

@get "/otera/loop" function()
    data = Dict("title" => "Greetings", "names" => ["Alice", "Bob", "Chris"])
    return render(data)  # This will return an HTML.Response with the rendered template
end
```

In this example, an Otera template is defined with a for-loop that iterates over a list of names, greeting each name.

Example 2: Running Julia Code in Otera Template
```julia
using OteraEngine
using Oxygen

# Define an Otera template with embedded Julia code
template_str = """
The square of {{ number }} is {< number^2 >}.
"""

# Create a render function for the Otera template
render = otera(template_str)

@get "/otera/square" function()
    data = Dict("number" => 5)
    return render(data)  # This will return an HTML.Response with the rendered template
end

```

In this example, an Otera template is defined with embedded Julia code that calculates the square of a given number. 

## Mounting Static Files

You can mount static files using this handy function which recursively searches a folder for files and mounts everything. All files are 
loaded into memory on startup.

```julia
using Oxygen

# mount all files inside the "content" folder under the "/static" path
staticfiles("content", "static")

# start the web server
serve()
```

## Mounting Dynamic Files 

Similar to staticfiles, this function mounts each path and re-reads the file for each request. This means that any changes to the files after the server has started will be displayed.

```julia
using Oxygen

# mount all files inside the "content" folder under the "/dynamic" path
dynamicfiles("content", "dynamic")

# start the web server
serve()
```
## Performance Tips

Disabling the internal logger can provide some massive performance gains, which can be helpful in some scenarios.
Anecdotally, i've seen a 2-3x speedup in `serve()` and a 4-5x speedup in `serveparallel()` performance.

```julia 
# This is how you disable internal logging in both modes
serve(access_log=nothing)
serveparallel(access_log=nothing)
```

## Logging

Oxygen provides a default logging format but allows you to customize the format using the `access_log` parameter. This functionality is available in both the `serve()` and `serveparallel()` functions.

You can read more about the logging options [here](https://juliaweb.github.io/HTTP.jl/stable/reference/#HTTP.@logfmt_str)

```julia 
# Uses the default logging format
serve()

# Customize the logging format 
serve(access_log=logfmt"[$time_iso8601] \"$request\" $status")

# Disable internal request logging 
serve(access_log=nothing)
```

## Middleware

Middleware functions make it easy to create custom workflows to intercept all incoming requests and outgoing responses.
They are executed in the same order they are passed in (from left to right).

They can be set at the application, router, and route layer with the `middleware` keyword argument. All middleware is additive and any middleware defined in these layers will be combined and executed.

Middleware will always be executed in the following order:

```
application -> router -> route
```

Now lets see some middleware in action:
```julia
using Oxygen
using HTTP

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS"
]

# https://juliaweb.github.io/HTTP.jl/stable/examples/#Cors-Server
function CorsMiddleware(handler)
    return function(req::HTTP.Request)
        println("CORS middleware")
        # determine if this is a pre-flight request from the browser
        if HTTP.method(req)=="OPTIONS"
            return HTTP.Response(200, CORS_HEADERS)  
        else 
            return handler(req) # passes the request to the AuthMiddleware
        end
    end
end

function AuthMiddleware(handler)
    return function(req::HTTP.Request)
        println("Auth middleware")
        # ** NOT an actual security check ** #
        if !HTTP.headercontains(req, "Authorization", "true")
            return HTTP.Response(403)
        else 
            return handler(req) # passes the request to your application
        end
    end
end

function middleware1(handle)
    function(req)
        println("middleware1")
        handle(req)
    end
end

function middleware2(handle)
    function(req)
        println("middleware2")
        handle(req)
    end
end

# set middleware at the router level
math = router("math", middleware=[middleware1])

# set middleware at the route level 
@get math("/divide/{a}/{b}", middleware=[middleware2]) function(req, a::Float64, b::Float64)
    return a / b
end

# set application level middleware
serve(middleware=[CorsMiddleware, AuthMiddleware])
```

## Built-in Middleware

Oxygen also ships with some prebuilt middleware functions so you can easily add bearer auth, rate limiting and CORS support to your app. You can add these at the application, router, or route level in your app—just pass them in with the `middleware` keyword and Oxygen will take care of the rest.


### RateLimiter

The `RateLimiter` middleware lets you set a cap on how many requests each client can make in a given time window. It's perfect for public endpoints, login routes, or anywhere you want to keep things smooth and prevent brute-force attacks. 

*The rate limiting is completely based on the `req.context[:ip]` property that's added to all requests. If you use proxies or services like cloudflare that intercept requests, you'll need to parse out the actuall callers ip from the headers and reassign the `ip` property on the `requet.context` object.*

**Example:**
```julia
# Limit each client to 50 requests every 3 seconds
serve(middleware=[RateLimiter(rate_limit=50, window_period=Second(3))])
```

Keyword Arguments:
- `rate_limit::Int`: Maximum number of requests allowed per IP within the window period. Default is 100.
- `window_period::Period`: Time window for rate limiting. Default is 1 minute.
- `cleanup_period::Period`: Interval for running the background cleanup task. Default is 10 minutes.
- `cleanup_threshold::Period`: Minimum age of inactive IP entries before deletion during cleanup. Default is 10 minutes.

---

### BearerAuth

In most serious applications, you'll find yourself needing to add some layer of authentication to your web app. In most cases
this means passing an `Authorization` header, extracting the token, and then validating it either against your custom oauth server or some external service. 

After authenticating a user, you'll typically want this object readily available to most if not all routes in your application, so your routes don't need to revalidate the user more than once.

The `BearerAuth` middleware does exactly this and extracts the bearer token from the authorization header and passes it to your custom function. If the token's good, your handler runs; if not, the request gets bounced.


**Example:**
```julia
# Your function will need to perform actual token validation 
function validate_token(token::String)
    # return the user object 
    return Dict("name" => "joe")
end

# Only let requests with a valid token through
serve(middleware=[BearerAuth(validate_token)])
```
Parameters:
- `validate_token`: Your function for checking if a token is legit. Return user info if it's good, or `nothing` or `missing` if not.

Keyword Arguments:
- `header`: The name of the header to check for the token (defaults to `"Authorization"`).
- `scheme`: The authentication scheme prefix in the header (defaults to `"Bearer"`).
---

### CORS

The `Cors` middleware handles Cross-Origin Resource Sharing (CORS) for your API. It sets the right headers and responds to preflight OPTIONS requests, so browsers can safely call your endpoints from other domains. Just configure your policy with keyword arguments and Oxygen will do the rest.

**Example:**
```julia
# Let any origin connect and expose a custom header
serve(middleware=[Cors(allowed_origins="*")])
```
- `allowed_origins`: Value for `Access-Control-Allow-Origin` (default: "*").
- `allowed_headers`: Value for `Access-Control-Allow-Headers` (default: "*").
- `allowed_methods`: Value for `Access-Control-Allow-Methods` (default: "GET, POST, OPTIONS").
- `allow_credentials`: If true, adds `Access-Control-Allow-Credentials: true`.
- `max_age`: If set, adds `Access-Control-Max-Age` header.
- `extra_headers`: Vector of additional key-value pairs to be added as extra CORS headers.


---

### Bringing it all together

In a more real-world example, you'll want to utilize all three of these together

1. `Cors` - Ensure the caller's domain is allowed to call this server
2. `RateLimiter` - Places a rate-limit limit on the caller's ip to prevent abuse
3. `BearerAuth` - See if the current user has access to the api

**Example:**
```julia
# Mix CORS, rate limiting, and auth for a super secure API
serve(middleware=[Cors(), RateLimiter(), BearerAuth(validate_token)])
```

As a reminder, you can use `RateLimiter` and `BearerAuth` middleware on the router and route level to have more fine grained limits and rates on select endpoints / resources.


**Example:**
```julia

# Your function will need to perform actual token validation 
function validate_token(token::String)
    # validate the token and lookup the user object
    # return the user object 
    return Dict("name" => "joe")
end

protected = router("/protected", middleware=[RateLimiter(rate_limit=50), BearerAuth(validate_token)])

# This route is protected behind both the global middlewware and a lower rate limit and the token bearer authentication
@get protected("/greet") function(req)
    name = req.context[:user]["name"]
    return text("hello $(name)!")
end

# This route is protected just by the global middleware
@get "/" function()
    return text("welcome to the server")
end

# Mix CORS, rate limiting, and auth for a super secure API
serve(middleware=[Cors(), RateLimiter(rate_limit=100)])
```

## Custom Response Serializers

If you don't want to use Oxygen's default response serializer, you can turn it off and add your own! Just create your own special middleware function to serialize the response and add it at the end of your own middleware chain. 

Both `serve()` and `serveparallel()` have a `serialize` keyword argument which can toggle off the default serializer.

```julia
using Oxygen
using HTTP
using JSON

@get "/divide/{a}/{b}" function(req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

# This is just a regular middleware function
function myserializer(handle)
    function(req)
        try
          response = handle(req)
          # convert all responses to JSON
          return HTTP.Response(200, [], body=JSON.json(response)) 
        catch error 
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The Server encountered a problem")
        end 
    end
end

# make sure 'myserializer' is the last middleware function in this list
serve(middleware=[myserializer], serialize=false)
```


## Autogenerated Docs with Swagger

Swagger documentation is automatically generated for each route you register in your application. Only the route name, parameter types, and 200 & 500 responses are automatically created for you by default. 

You can view your generated documentation at `/docs`, and the schema
can be found under `/docs/schema`. Both of these values can be changed to whatever you want using the `configdocs()` function. You can also opt out of autogenerated docs entirely by calling the `disabledocs()` function 
before starting your application. 

To add additional details you can either use the built-in `mergeschema()` or `setschema()`
functions to directly modify the schema yourself or merge the generated schema from the `SwaggerMarkdown.jl` package (I'd recommend the latter)

Below is an example of how to merge the schema generated from the `SwaggerMarkdown.jl` package.
```julia
using Oxygen
using SwaggerMarkdown

# Here's an example of how you can merge autogenerated docs from SwaggerMarkdown.jl into your api
@swagger """
/divide/{a}/{b}:
  get:
    description: Return the result of a / b
    parameters:
      - name: a
        in: path
        required: true
        description: this is the value of the numerator 
        schema:
          type : number
    responses:
      '200':
        description: Successfully returned an number.
"""
@get "/divide/{a}/{b}" function (req, a::Float64, b::Float64)
    return a / b
end

# title and version are required
info = Dict("title" => "My Demo Api", "version" => "1.0.0")
openApi = OpenAPI("3.0", info)
swagger_document = build(openApi)
  
# merge the SwaggerMarkdown schema with the internal schema
mergeschema(swagger_document)

# start the web server
serve()
```

Below is an example of how to manually modify the schema
```julia
using Oxygen
using SwaggerMarkdown

# Only the basic information is parsed from this route when generating docs
@get "/multiply/{a}/{b}" function (req, a::Float64, b::Float64)
    return a * b
end

# Here's an example of how to update a part of the schema yourself
mergeschema("/multiply/{a}/{b}", 
  Dict(
    "get" => Dict(
      "description" => "return the result of a * b"
    )
  )
)

# Here's another example of how to update a part of the schema yourself, but this way allows you to modify other properties defined at the root of the schema (title, summary, etc.)
mergeschema(
  Dict(
    "paths" => Dict(
      "/multiply/{a}/{b}" => Dict(
        "get" => Dict(
          "description" => "return the result of a * b"
        )
      )
    )
  )
)
```


# API Reference (macros)

#### @get, @post, @put, @patch, @delete
```julia
  @get(path, func)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `path` | `string` or `router()` | **Required**. The route to register |
| `func` | `function` | **Required**. The request handler for this route |

Used to register a function to a specific endpoint to handle that corresponding type of request

#### @route
```julia
  @route(methods, path, func)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `methods` | `array` | **Required**. The types of HTTP requests to register to this route|
| `path` | `string` or `router()` | **Required**. The route to register |
| `func` | `function` | **Required**. The request handler for this route |

Low-level macro that allows a route to be handle multiple request types


#### staticfiles
```julia
  staticfiles(folder, mount)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `folder` | `string` | **Required**. The folder to serve files from |
| `mountdir` | `string` | The root endpoint to mount files under (default is "static")|
| `set_headers` | `function` | Customize the http response headers when returning these files |
| `loadfile` | `function` | Customize behavior when loading files |

Serve all static files within a folder. This function recursively searches a directory
and mounts all files under the mount directory using their relative paths.

#### dynamicfiles

```julia
  dynamicfiles(folder, mount)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `folder` | `string` | **Required**. The folder to serve files from |
| `mountdir` | `string` | The root endpoint to mount files under (default is "static")|
| `set_headers` | `function` | Customize the http response headers when returning these files |
| `loadfile` | `function` | Customize behavior when loading files |

Serve all static files within a folder. This function recursively searches a directory
and mounts all files under the mount directory using their relative paths. The file is loaded
on each request, potentially picking up any file changes.

### Request helper functions

#### html()
```julia
  html(content, status, headers)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `content` | `string` | **Required**. The string to be returned as HTML |
| `status` | `integer` | The HTTP response code (default is 200)|
| `headers` | `dict` | The headers for the HTTP response (default has content-type header set to "text/html; charset=utf-8") |

Helper function to designate when content should be returned as HTML


#### queryparams()
```julia
  queryparams(request)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |

Returns the query parameters from a request as a Dict()

### Body Functions

#### text()
```julia
  text(request)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |

Returns the body of a request as a string

#### binary()
```julia
  binary(request)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |

Returns the body of a request as a binary file (returns a vector of `UInt8`s)

#### json()
```julia
  json(request, class_type)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |
| `class_type` | `struct` | A struct to deserialize a JSON object into |

Deserialize the body of a request into a julia struct
