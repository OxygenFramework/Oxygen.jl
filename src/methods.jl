# This is where methods are coupled to a global state

"""
    resetstate()

Reset all the internal state variables
"""
function resetstate()
    # prevent context reset when created at compile-time
    if (@__MODULE__) == Oxygen
        CONTEXT[] = Oxygen.Core.ServerContext()
    end
end

function context()
    app_ctx = CONTEXT[].app_context[]
    return ismissing(app_ctx) ? missing : app_ctx.payload
end

function serve(; kwargs...) 
    async = Base.get(kwargs, :async, false)
    try
        # return the resulting HTTP.Server object
        return Oxygen.Core.serve(CONTEXT[]; kwargs...)
    finally
        # close server on exit if we aren't running asynchronously
        if !async 
            terminate()
            # only reset state on exit if we aren't running asynchronously & are running it interactively 
            isinteractive() && resetstate()
        end
    end
end


"""
    serveparallel(; middleware::Vector=[], handler=stream_handler, host="127.0.0.1", port=8080, serialize=true, async=false, catch_errors=true, docs=true, metrics=true, kwargs...)

"""
function serveparallel(; kwargs...)
    serve(; parallel = true, kwargs...)
end


### Routing Macros ###

"""
    @get(path::String, func::Function)

Used to register a function to a specific endpoint to handle GET requests  
"""
macro get(path, func)
    path, func = adjustparams(path, func)
    :(@route [GET] $(esc(path)) $(esc(func)))
end

"""
    @post(path::String, func::Function)

Used to register a function to a specific endpoint to handle POST requests
"""
macro post(path, func)
    path, func = adjustparams(path, func)
    :(@route [POST] $(esc(path)) $(esc(func)))
end

"""
    @put(path::String, func::Function)

Used to register a function to a specific endpoint to handle PUT requests
"""
macro put(path, func)
    path, func = adjustparams(path, func)
    :(@route [PUT] $(esc(path)) $(esc(func)))
end

"""
    @patch(path::String, func::Function)

Used to register a function to a specific endpoint to handle PATCH requests
"""
macro patch(path, func)
    path, func = adjustparams(path, func)
    :(@route [PATCH] $(esc(path)) $(esc(func)))
end

"""
    @delete(path::String, func::Function)

Used to register a function to a specific endpoint to handle DELETE requests
"""
macro delete(path, func)
    path, func = adjustparams(path, func)
    :(@route [DELETE] $(esc(path)) $(esc(func)))
end

"""
    @stream(path::String, func::Function)

Used to register a function to a specific endpoint to handle Streaming requests
"""
macro stream(path, func)
    path, func = adjustparams(path, func)
    :(@route [STREAM] $(esc(path)) $(esc(func)))
end

"""
    @websocket(path::String, func::Function)

Used to register a function to a specific endpoint to handle WebSocket connections
"""
macro websocket(path, func)
    path, func = adjustparams(path, func)
    :(@route [WEBSOCKET] $(esc(path)) $(esc(func)))
end


"""
    @route(methods::Array{String}, path::String, func::Function)

Used to register a function to a specific endpoint to handle mulitiple request types
"""
macro route(methods, path, func)
    :(route($(esc(methods)), $(esc(path)), $(esc(func))))
end


"""
    adjustparams(path, func)

Adjust the order of `path` and `func` based on their types. This is used to support the `do ... end` syntax for 
the routing macros.
"""
function adjustparams(path, func)
    # case 1: do ... end block syntax was used
    if isa(path, Expr) && path.head == :->
        func, path
    # case 2: regular syntax was used
    else
        path, func
    end
end

function adjustparams(description, parameters, func)
    # case 1: do ... end block syntax was used
    if isa(description, Expr) && description.head == :->
        parameters, func, description
    # case 2: regular syntax was used
    else
        description, parameters, func
    end
end

### Core Routing Functions ###

function route(methods::Vector{String}, path::Union{String,HOFRouter}, func::Function)
    for method in methods
        Oxygen.Core.register(CONTEXT[], method, path, func)
    end
end

# This variation supports the do..block syntax
route(func::Function, methods::Vector{String}, path::Union{String,HOFRouter}) = route(methods, path, func)

### Special Routing Functions Support for do..end Syntax ###

"""
    stream(func::Function, path::String)
    stream(func::Function, path::HOFRouter)

Convenience function to register a STREAM route. Equivalent to `@stream`.
"""
stream(func::Function, path::String)    = route([STREAM], path, func)
stream(func::Function, path::HOFRouter) = route([STREAM], path, func)

"""
    websocket(func::Function, path::String)
    websocket(func::Function, path::HOFRouter)

Convenience function to register a WEBSOCKET route. Equivalent to `@websocket`.
"""
websocket(func::Function, path::String)     = route([WEBSOCKET], path, func)
websocket(func::Function, path::HOFRouter)  = route([WEBSOCKET], path, func)

### Core Routing Functions Support for do..end Syntax ###

"""
    get(func::Function, path::String)
    get(func::Function, path::HOFRouter)

Convenience function to register a GET route. Equivalent to `@get`.
"""
get(func::Function, path::String)       = route([GET], path, func)
get(func::Function, path::HOFRouter)    = route([GET], path, func)

"""
    post(func::Function, path::String)
    post(func::Function, path::HOFRouter)

Convenience function to register a POST route. Equivalent to `@post`.
"""
post(func::Function, path::String)      = route([POST], path, func)
post(func::Function, path::HOFRouter)   = route([POST], path, func)

"""
    put(func::Function, path::String)
    put(func::Function, path::HOFRouter)

Convenience function to register a PUT route. Equivalent to `@put`.
"""
put(func::Function, path::String)       = route([PUT], path, func) 
put(func::Function, path::HOFRouter)    = route([PUT], path, func) 

"""
    patch(func::Function, path::String)
    patch(func::Function, path::HOFRouter)

Convenience function to register a PATCH route. Equivalent to `@patch`.
"""
patch(func::Function, path::String)     = route([PATCH], path, func)
patch(func::Function, path::HOFRouter)  = route([PATCH], path, func)

"""
    delete(func::Function, path::String)
    delete(func::Function, path::HOFRouter)

Convenience function to register a DELETE route. Equivalent to `@delete`.
"""
delete(func::Function, path::String)    = route([DELETE], path, func)
delete(func::Function, path::HOFRouter) = route([DELETE], path, func)


### MCP Tool Registration ###

"""
    tool(description::String, parameters, func::Function; name=nothing)

Convenience function to register an MCP tool. Equivalent to `@tool`
"""
tool(description::String, parameters, func::Function; name=nothing) = Oxygen.Core.register_tool!(CONTEXT[], string(description), parameters, func; name=name)

"""
    tool(func::Function, description::String, parameters; name=nothing)
Convenience function to register an MCP tool. Equivalent to `@tool`
"""
tool(func::Function, description::String, parameters; name=nothing) = tool(description, parameters, func; name=name)

"""
    tool(parameters, func::Function; name=nothing)

Convenience function to register an MCP tool without an explicit description:
the function's own docstring is used as the tool description. Equivalent to the
two-argument `@tool`.
"""
tool(parameters, func::Function; name=nothing) = Oxygen.Core.register_tool!(CONTEXT[], "", parameters, func; name=name)


"""
    @tool(description::String, parameters, func::Function)

Used to register a function as an MCP tool. Metadata may span multiple lines,
but the `function` keyword must sit on the same line as the closing metadata
token. A block form is also supported (and reads closest to `@doc`):

    @tool "description" Dict(:param => "description") begin
        function name(...)
            ...
        end
    end
"""
macro tool(description, parameters, func)
    description, parameters, func = adjustparams(description, parameters, func)
    return :(tool($(esc(description)), $(esc(parameters)), $(esc(func))))
end

"""
    @tool(parameters, func::Function)

Used to register a function as an MCP tool using the function's docstring as the
tool description. The handler must be a named definition written inline, so the
macro can attach the preceding docstring to it:

    \"\"\"
    Add two integers together.
    \"\"\"
    @tool Dict(:a => "the first addend", :b => "the second addend") function add(a::Int, b::Int)
        a + b
    end

An undocumented handler gets an empty description.
"""
macro tool(parameters, func)
    parameters, func = adjustparams(parameters, func)
    name = Oxygen.Core.Reflection.defname(func)
    if isnothing(name)
        return :(tool($(esc(parameters)), $(esc(func))))
    end
    # Split the definition into its own `@__doc__`-marked statement so Julia
    # attaches the preceding docstring to the handler, then register it.
    return esc(quote
        Base.@__doc__ $func
        tool($parameters, $name)
    end)
end


### MCP Prompt Registration ###

"""
    prompt(description::String, func::Function; name=nothing)

Convenience function to register an MCP prompt. Equivalent to `@prompt`.

The prompt's arguments are inferred from `func`'s signature — each parameter
(excluding the injected `context`/`request`) becomes a template variable, and
parameters without a default are marked required. No parameter description map
is needed; adding a parameter adds a template variable.
"""
prompt(description::String, func::Function; name=nothing) = Oxygen.Core.register_prompt!(CONTEXT[], string(description), func; name=name)

"""
    prompt(func::Function, description::String; name=nothing)

Convenience function to register an MCP prompt. Equivalent to `@prompt`.
"""
prompt(func::Function, description::String; name=nothing) = prompt(description, func; name=name)


"""
    @prompt(description::String, func::Function)

Used to register a function as an MCP prompt. The prompt's arguments are taken
from the function signature, so the handler parameters *are* the template
variables:

    @prompt "Report on a city" function city_report(city::String, tone::String = "formal")
        "Write a \$tone report about \$city"
    end

A block form is also supported:

    @prompt "Report on a city" begin
        function city_report(city::String)
            "Write a report about \$city"
        end
    end
"""
macro prompt(description, func)
    return :(prompt($(esc(description)), $(esc(func))))
end


### MCP Resource Registration ###

"""
    resource(uri::String, description::String, func::Function; name=nothing, title=nothing, mime_type=nothing, size=nothing, annotations=nothing, icons=nothing)

Convenience function to register an MCP resource. Equivalent to `@resource`.

A `uri` carrying `{var}` (or reserved `{+var}`) placeholders is registered as a
resource template; the handler's parameters (excluding the injected
`context`/`request`) are the template variables. A plain `uri` is registered as
a static resource whose handler takes no arguments. `name` defaults to the
handler's name, and `mime_type` becomes the default content type of
`resources/read` replies. `annotations` accepts the spec's
`audience`/`priority`/`lastModified` fields and `icons` a `src` string or an
icon dict/vector.
"""
resource(uri::String, description::String, func::Function; kwargs...) =
    Oxygen.Core.register_resource!(CONTEXT[], uri, string(description), func; kwargs...)

"""
    resource(uri::String, func::Function; name=nothing, ...)

Convenience function to register an MCP resource without an explicit
description: the function's own docstring is used as the resource description.
Equivalent to the two-argument `@resource`.
"""
resource(uri::String, func::Function; kwargs...) =
    Oxygen.Core.register_resource!(CONTEXT[], uri, "", func; kwargs...)


"""
    resource(func::Function, uri::String, description::String; name=nothing, ...)

Convenience function to register an MCP resource. Equivalent to `@resource`, and
supports the `do ... end` form.
"""
resource(func::Function, uri::String, description::String; kwargs...) =
    resource(uri, description, func; kwargs...)

"""
    resource(func::Function, uri::String; name=nothing, ...)

Convenience function to register an MCP resource using the handler's docstring
as the description. Equivalent to the two-argument `@resource`, and supports the
`do ... end` form.
"""
resource(func::Function, uri::String; kwargs...) =
    resource(uri, func; kwargs...)


"""
    resource_folder(prefix::String, directory::String; name=nothing, description=nothing,
                    title=nothing, hidden=false, mime_types=nothing,
                    annotations=nothing, icons=nothing)

Register a resource template at `prefix * "{+path}"` that serves regular files
below `directory`, so nested paths work:

    resource_folder("file:///srv/data", "/srv/data")
    # file:///srv/data/readme.md reads /srv/data/readme.md

Requests are sanitized before touching the filesystem: `.`/`..`/backslash
segments, NUL bytes (`:` on Windows), and (unless `hidden=true`) dotfiles are
rejected, and the resolved target is verified with `realpath` to still be
inside `directory`, so symlinks cannot escape. `mime_types` maps an extension
(with or without the leading dot, matched case-insensitively) to a MIME type;
otherwise a small built-in table and `HTTP.sniff` decide. A missing or
non-regular file is reported as the spec's resource-not-found error for the
request's protocol era.
"""
resource_folder(prefix::AbstractString, directory::AbstractString; kwargs...) =
    Oxygen.Core.MCP.register_resource_folder!(CONTEXT[], string(prefix), string(directory); kwargs...)


"""
    @resource(uri::String, description::String, func::Function)

Used to register a function as an MCP resource or resource template. A URI with
`{var}` placeholders makes the handler's parameters the template variables:

    @resource "oxygen://docs/{page}" "Look up a docs page" function docs(page::String)
        "docs for \$page"
    end

A URI without placeholders registers a static resource:

    @resource "oxygen://readme" "Project readme" function readme()
        read("README.md", String)
    end

The two-argument form uses the handler's docstring as the description:

    \"\"\"
    Project readme.
    \"\"\"
    @resource "oxygen://readme" function readme()
        read("README.md", String)
    end

A block form is also supported (and reads closest to `@doc`):

    @resource "oxygen://docs/{page}" "Look up a docs page" begin
        function docs(page::String)
            ...
        end
    end
"""
macro resource(uri, description, func)
    uri, description, func = adjustparams(uri, description, func)
    return :(resource($(esc(uri)), $(esc(description)), $(esc(func))))
end

"""
    @resource(uri::String, func::Function)

Used to register a function as an MCP resource using the function's own
docstring as the description. The handler must be a named definition written
inline, so the macro can attach the preceding docstring to it.
"""
macro resource(uri, func)
    uri, func = adjustparams(uri, func)
    name = Oxygen.Core.Reflection.defname(func)
    if isnothing(name)
        return :(resource($(esc(uri)), $(esc(func))))
    end
    return esc(quote
        Base.@__doc__ $func
        resource($uri, $name)
    end)
end



### MCP Change Notifications ###

"""
    notify_resource_updated(uri::AbstractString)::Int

Announce that a resource's contents changed: modern `subscriptions/listen`
streams watching `uri` receive `notifications/resources/updated`, and a legacy
session subscribed via `resources/subscribe` receives it on its server→client
channel (stdio stdout or the GET SSE stream). Returns the number of streams the
notification was enqueued on.
"""
notify_resource_updated(uri::AbstractString)::Int =
    Oxygen.Core.MCP.notify_resource_updated(CONTEXT[], uri)

"""
    notify_resources_changed()::Int

Announce that the server's resource list changed
(`notifications/resources/list_changed`). Returns the number of streams the
notification was enqueued on.
"""
notify_resources_changed()::Int =
    Oxygen.Core.MCP.notify_resources_changed(CONTEXT[])

"""
    notify_tools_changed()::Int

Announce that the server's tool list changed
(`notifications/tools/list_changed`). Returns the number of streams the
notification was enqueued on.
"""
notify_tools_changed()::Int =
    Oxygen.Core.MCP.notify_tools_changed(CONTEXT[])

"""
    notify_prompts_changed()::Int

Announce that the server's prompt list changed
(`notifications/prompts/list_changed`). Returns the number of streams the
notification was enqueued on.
"""
notify_prompts_changed()::Int =
    Oxygen.Core.MCP.notify_prompts_changed(CONTEXT[])


"""
    @staticfiles(folder::String, mountdir::String, headers::Vector{Pair{String,String}}=[])

Mount all files inside the /static folder (or user defined mount point)
"""
macro staticfiles(folder, mountdir="static", headers=[])
    printstyled(stderr, "@staticfiles macro is deprecated, please use the staticfiles() function instead\n", color = :red, bold = true) 
    quote
        staticfiles($(esc(folder)), $(esc(mountdir)); headers=$(esc(headers))) 
    end
end


"""
    @dynamicfiles(folder::String, mountdir::String, headers::Vector{Pair{String,String}}=[])

Mount all files inside the /static folder (or user defined mount point), 
but files are re-read on each request
"""
macro dynamicfiles(folder, mountdir="static", headers=[])
    printstyled(stderr, "@dynamicfiles macro is deprecated, please use the dynamicfiles() function instead\n", color = :red, bold = true) 
    quote
        dynamicfiles($(esc(folder)), $(esc(mountdir)); headers=$(esc(headers))) 
    end      
end


staticfiles(
    folder::String, 
    mountdir::String="static"; 
    headers::Vector=[], 
    loadfile::Nullable{Function}=nothing
) = Oxygen.Core.staticfiles(CONTEXT[], CONTEXT[].service.router, folder, mountdir; headers, loadfile)


dynamicfiles(
    folder::String, 
    mountdir::String="static"; 
    headers::Vector=[], 
    loadfile::Nullable{Function}=nothing
) = Oxygen.Core.dynamicfiles(CONTEXT[], CONTEXT[].service.router, folder, mountdir; headers, loadfile)

"""
    getexternalurl()

Return the external URL of the service
"""
function getexternalurl() :: String
    external_url = CONTEXT[].service.external_url[]
    if isnothing(external_url)
        error("getexternalurl() is only available when the service is running")
    end
    return external_url
end

"""
    internalrequest(req::Oxygen.Request; middleware::Vector=[], metrics::Bool=false, serialize::Bool=true, catch_errors=true)

Sends an internal request to the server, allowing for communication between different parts of the application.
"""
internalrequest(req::Oxygen.Request; middleware::Vector=[], metrics::Bool=false, serialize::Bool=true, catch_errors=true) = 
    Oxygen.Core.internalrequest(CONTEXT[], req; middleware, metrics, serialize, catch_errors)

"""
    router(prefix::String = ""; 
                tags::Vector{String} = Vector{String}(), 
                middleware::Nullable{Vector} = nothing, 
                interval::Nullable{Real} = nothing,
                cron::Nullable{String} = nothing,
                mcp::Nullable{MCPMetadata} = nothing)

Create a new router instance.

# Arguments
- `prefix::String`: A string to be prefixed to all routes in this router.
- `tags::Vector{String}`: A vector of strings to tag the router for documentation and management purposes.
- `middleware::Nullable{Vector}`: Optional middleware to be applied to all routes in the router.
- `interval::Nullable{Real}`: Optional interval for scheduling tasks.
- `cron::Nullable{String}`: Optional cron expression for scheduling tasks.
- `mcp`: Optional MCP metadata inherited by every route in the router. Use
  `mcp = false` to exclude the group, `mcp = true` to expose each route with
  defaults, or a `NamedTuple`/`Dict` such as
  `(description = "User management", parameters = Dict(:id => "User ID"))` to
  provide defaults that routes can override.

# Returns
A router instance that can be used to define and manage a set of related routes.
"""
function router(prefix::String = ""; 
                tags::Vector{String} = Vector{String}(), 
                middleware::Nullable{Vector} = nothing, 
                interval::Nullable{Real} = nothing,
                cron::Nullable{String} = nothing,
                mcp::Nullable{MCPMetadata} = nothing)

    return Oxygen.Core.router(CONTEXT[], prefix; tags, middleware, interval, cron, mcp)
end


mergeschema(route::String, customschema::Dict) = Oxygen.Core.mergeschema(CONTEXT[].docs.schema, route, customschema)
mergeschema(customschema::Dict) = Oxygen.Core.mergeschema(CONTEXT[].docs.schema, customschema)


"""
    getschema()

Return the current internal schema for this app
"""
function getschema()
    return CONTEXT[].docs.schema
end


"""
    setschema(customschema::Dict)

Overwrites the entire internal schema
"""
function setschema(customschema::Dict)
    empty!(CONTEXT[].docs.schema)
    merge!(CONTEXT[].docs.schema, customschema)
    return
end


"""
    @repeat(interval::Real, func::Function)

Registers a repeat task. This will extract either the function name 
or the random Id julia assigns to each lambda function. 
"""
macro repeat(interval, func)
    quote 
        Oxygen.Core.task($(CONTEXT[].tasks.registered_tasks), $(esc(interval)), string($(esc(func))), $(esc(func)))
    end
end

"""
@repeat(interval::Real, name::String, func::Function)

This variation provides way manually "name" a registered repeat task. This information 
is used by the server on startup to log out all cron jobs.
"""
macro repeat(interval, name, func)
    quote 
        Oxygen.Core.task($(CONTEXT[].tasks.registered_tasks), $(esc(interval)), string($(esc(name))), $(esc(func)))
    end
end

"""
    @cron(expression::String, func::Function)

Registers a function with a cron expression. This will extract either the function name 
or the random Id julia assigns to each lambda function. 
"""
macro cron(expression, func)
    quote 
        Oxygen.Core.cron($(CONTEXT[].cron.registered_jobs), $(esc(expression)), string($(esc(func))), $(esc(func)))
    end
end


"""
    @cron(expression::String, name::String, func::Function)

This variation provides way manually "name" a registered function. This information 
is used by the server on startup to log out all cron jobs.
"""
macro cron(expression, name, func)
    quote 
        Oxygen.Core.cron($(CONTEXT[].cron.registered_jobs), $(esc(expression)), string($(esc(name))), $(esc(func)))
    end
end

## Cron Job Functions ##

"""
    startcronjobs(ctx::ServerContext)
    startcronjobs()

Start all registered cron jobs.
"""
function startcronjobs(ctx::ServerContext)
    Oxygen.Core.registercronjobs(ctx)
    Oxygen.Core.startcronjobs(ctx.cron)
end

startcronjobs() = startcronjobs(CONTEXT[])

"""
    stopcronjobs(ctx::ServerContext)
    stopcronjobs()

Stop all running cron jobs.
"""
stopcronjobs(ctx::ServerContext) = Oxygen.Core.stopcronjobs(ctx.cron)
stopcronjobs() = stopcronjobs(CONTEXT[])

"""
    clearcronjobs(ctx::ServerContext)
    clearcronjobs()

Clear all registered cron jobs.
"""
clearcronjobs(ctx::ServerContext) = Oxygen.Core.clearcronjobs(ctx.cron)
clearcronjobs() = clearcronjobs(CONTEXT[])

### Repeat Task Functions ###

"""
    starttasks(context::ServerContext)
    starttasks()

Start all registered repeat tasks.
"""
function starttasks(context::ServerContext) 
    Oxygen.Core.registertasks(context)
    Oxygen.Core.starttasks(context.tasks)
end

starttasks() = starttasks(CONTEXT[])

"""
    stoptasks(context::ServerContext)
    stoptasks()

Stop all running repeat tasks.
"""
stoptasks(context::ServerContext) = Oxygen.Core.stoptasks(context.tasks)
stoptasks() = stoptasks(CONTEXT[])

"""
    cleartasks(context::ServerContext)
    cleartasks()

Clear all registered repeat tasks.
"""
cleartasks(context::ServerContext) = Oxygen.Core.cleartasks(context.tasks)
cleartasks() = cleartasks(CONTEXT[])


### Terminate Function ###

"""
    terminate(context::ServerContext)
    terminate()

Terminate the server and stop all running tasks.
"""
terminate(context::ServerContext) = Oxygen.Core.terminate(context)
terminate() = terminate(CONTEXT[])


### Setup Docs Strings ###


for method in [:serve, :terminate, :staticfiles, :dynamicfiles,  :internalrequest]
    eval(quote
        @doc (@doc(Oxygen.Core.$method)) $method
    end)
end


# Docs Methods
for method in [:router, :mergeschema]
    eval(quote
        @doc (@doc(Oxygen.Core.AutoDoc.$method)) $method
    end)
end

# Repeat Task methods
for method in [:starttasks, :stoptasks, :cleartasks]
    eval(quote
        @doc (@doc(Oxygen.Core.RepeatTasks.$method)) $method
    end)
end


# Cron methods
for method in [:startcronjobs, :stopcronjobs, :clearcronjobs]
    eval(quote
        @doc (@doc(Oxygen.Core.Cron.$method)) $method
    end)
end

