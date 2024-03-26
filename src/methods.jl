# This is where methods are coupled to a global state

"""
    resetstate()

Reset all the internal state variables
"""
function resetstate()
    # prevent context reset when created at compile-time
    if (@__MODULE__) == Oxygen
        CONTEXT[] = Oxygen.Core.Context()
    end
end

function serve(; 
    middleware  = [], 
    handler     = Oxygen.Core.stream_handler, 
    host        = "127.0.0.1", 
    port        = 8080, 
    serialize   = true, 
    async       = false, 
    catch_errors= true, 
    docs        = true,
    metrics     = true, 
    show_errors = true,
    show_banner  = true,
    docs_path    = "/docs",
    schema_path  = "/schema",
    kwargs...) 

    try
        server = Oxygen.Core.serve(CONTEXT[]; 
            middleware  = middleware,
            handler     = handler,
            host        = host, 
            port        = port, 
            serialize   = serialize, 
            async       = async, 
            catch_errors= catch_errors, 
            docs        = docs,
            metrics     = metrics,
            show_errors = show_errors,
            show_banner = show_banner,
            docs_path   = docs_path,
            schema_path = schema_path,
            kwargs...
        )

        # return the resulting HTTP.Server object
        return server

    finally
        
        # close server on exit if we aren't running asynchronously
        if !async 
            terminate()
            # only reset state on exit if we aren't running asynchronously & are running it interactively 
            isinteractive() && resetstate()
        end

    end
end


function serveparallel(; 
    middleware  = [], 
    handler     = Oxygen.Core.stream_handler, 
    host        = "127.0.0.1", 
    port        = 8080, 
    serialize   = true, 
    async       = false, 
    catch_errors= true,
    docs        = true,
    metrics     = true, 
    show_errors = true,
    show_banner  = true,
    docs_path    = "/docs",
    schema_path  = "/schema",
    kwargs...)

    try
        server = Oxygen.Core.serveparallel(CONTEXT[];
            middleware  = middleware,
            handler     = handler, 
            host        = host,
            port        = port,
            serialize   = serialize, 
            async       = async, 
            catch_errors= catch_errors,
            docs        = docs,
            metrics     = metrics, 
            show_errors = show_errors,
            show_banner = show_banner,
            docs_path   = docs_path,
            schema_path = schema_path,
            kwargs...
        )

        # return the resulting HTTP.Server object
        return server

    finally 
        # close server on exit if we aren't running asynchronously
        if !async 
            terminate()
            # only reset state on exit if we aren't running asynchronously & are running it interactively 
            isinteractive() && resetstate()
        end
    end
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

Used to register a function to a specific endpoint to handle Server-Sent-Event requests
"""
macro stream(path, func)
    path, func = adjustparams(path, func)
    :(@route [STREAM] $(esc(path)) $(esc(func)))
end

"""
    @ws(path::String, func::Function)

Used to register a function to a specific endpoint to handle WebSocket requests
"""
macro ws(path, func)
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

### Core Routing Functions ###

function route(methods::Vector{String}, path::Union{String,Function}, func::Function)
    for method in methods
        Oxygen.Core.register(CONTEXT[], method, path, func)
    end
end

# This variation supports the do..block syntax
route(func::Function, methods::Vector{String}, path::Union{String,Function}) = route(methods, path, func)

### Special Routing Functions Support for do..end Syntax ###

stream(func::Function, path::String)    = route([STREAM], path, func)
stream(func::Function, path::Function)  = route([STREAM], path, func)

ws(func::Function, path::String)    = route([WEBSOCKET], path, func)
ws(func::Function, path::Function)  = route([WEBSOCKET], path, func)

### Core Routing Functions Support for do..end Syntax ###

get(func::Function, path::String)       = route([GET], path, func)
get(func::Function, path::Function)     = route([GET], path, func)

post(func::Function, path::String)      = route([POST], path, func)
post(func::Function, path::Function)    = route([POST], path, func)

put(func::Function, path::String)       = route([PUT], path, func) 
put(func::Function, path::Function)     = route([PUT], path, func) 

patch(func::Function, path::String)     = route([PATCH], path, func)
patch(func::Function, path::Function)   = route([PATCH], path, func)

delete(func::Function, path::String)    = route([DELETE], path, func)
delete(func::Function, path::Function)  = route([DELETE], path, func)



"""
    @staticfiles(folder::String, mountdir::String, headers::Vector{Pair{String,String}}=[])

Mount all files inside the /static folder (or user defined mount point)
"""
macro staticfiles(folder, mountdir="static", headers=[])
    printstyled("@staticfiles macro is deprecated, please use the staticfiles() function instead\n", color = :red, bold = true) 
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
    printstyled("@dynamicfiles macro is deprecated, please use the dynamicfiles() function instead\n", color = :red, bold = true) 
    quote
        dynamicfiles($(esc(folder)), $(esc(mountdir)); headers=$(esc(headers))) 
    end      
end


staticfiles(
    folder::String, 
    mountdir::String="static"; 
    headers::Vector=[], 
    loadfile::Nullable{Function}=nothing
) = Oxygen.Core.staticfiles(CONTEXT[].service.router, folder, mountdir; headers, loadfile)


dynamicfiles(
    folder::String, 
    mountdir::String="static"; 
    headers::Vector=[], 
    loadfile::Nullable{Function}=nothing
) = Oxygen.Core.dynamicfiles(CONTEXT[].service.router, folder, mountdir; headers, loadfile)


internalrequest(req::Oxygen.Request; middleware::Vector=[], metrics::Bool=false, serialize::Bool=true, catch_errors=true) = 
    Oxygen.Core.internalrequest(CONTEXT[], req; middleware, metrics, serialize, catch_errors)

function router(prefix::String = ""; 
                tags::Vector{String} = Vector{String}(), 
                middleware::Nullable{Vector} = nothing, 
                interval::Nullable{Real} = nothing,
                cron::Nullable{String} = nothing)

    return Oxygen.Core.AutoDoc.router(CONTEXT[], prefix; tags, middleware, interval, cron)
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

function startcronjobs(ctx::Context)
    Oxygen.Core.registercronjobs(ctx)
    Oxygen.Core.startcronjobs(ctx.cron)
end

startcronjobs() = startcronjobs(CONTEXT[])

stopcronjobs(ctx::Context) = Oxygen.Core.stopcronjobs(ctx.cron)
stopcronjobs() = stopcronjobs(CONTEXT[])

clearcronjobs(ctx::Context) = Oxygen.Core.clearcronjobs(ctx.cron)
clearcronjobs() = clearcronjobs(CONTEXT[])

### Repeat Task Functions ###

function starttasks(context::Context) 
    Oxygen.Core.registertasks(context)
    Oxygen.Core.starttasks(context.tasks)
end

starttasks() = starttasks(CONTEXT[])


stoptasks(context::Context) = Oxygen.Core.stoptasks(context.tasks)
stoptasks() = stoptasks(CONTEXT[])

cleartasks(context::Context) = Oxygen.Core.cleartasks(context.tasks)
cleartasks() = cleartasks(CONTEXT[])


### Terminate Function ###

terminate(context::Context) = Oxygen.Core.terminate(context)
terminate() = terminate(CONTEXT[])


### Setup Docs Strings ###


for method in [:serve, :serveparallel, :terminate, :staticfiles, :dynamicfiles,  :internalrequest]
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

