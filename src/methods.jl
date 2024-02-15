# This is where methods are coupled to a global state

"""
Reset all the internal state variables
"""
function resetstate()

    SERVICE[] = nothing

    # prevent context reset when created at compile-time
    if (@__MODULE__) == Oxygen
        CONTEXT[] = Oxygen.Core.Context()
    end
end

# Nothing to do for the router
"""
    terminate([service])

stops the webserver immediately
"""
terminate(service::Oxygen.Service) = Oxygen.Core.terminate(service)

function terminate()
    if !isnothing(SERVICE[]) 
        terminate(SERVICE[])
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
    docspath    = "/docs",
    schemapath  = "/schema",
    kwargs...) 

    try

        SERVICE[] = Oxygen.Core.serve(CONTEXT[]; 
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
            docspath    = docspath,
            schemapath  = schemapath,
            kwargs...
        )

        return SERVICE[]

    finally
        
        # close server on exit if we aren't running asynchronously
        if !async 
            terminate()
        end

        # only reset state on exit if we aren't running asynchronously & are running it interactively 
        if !async && isinteractive()
            resetstate()
        end

    end
end


function serveparallel(; 
    middleware  = [], 
    handler     = Oxygen.Core.stream_handler, 
    host        = "127.0.0.1", 
    port        = 8080, 
    queuesize   = 1024, 
    serialize   = true, 
    async       = false, 
    catch_errors= true,
    docs        = true,
    metrics     = true, 
    show_errors = true,
    docspath    = "/docs",
    schemapath  = "/schema",
    kwargs...)
    

    try
        SERVICE[] = Oxygen.Core.serveparallel(CONTEXT[];
            middleware  = middleware,
            handler     = handler, 
            host        = host,
            port        = port,
            queuesize   = queuesize,
            serialize   = serialize, 
            async       = async, 
            catch_errors= catch_errors,
            docs        = docs,
            metrics     = metrics, 
            show_errors = show_errors,
            docspath    = docspath,
            schemapath  = schemapath,
            kwargs...
        )

        return SERVICE[]

    finally 

        # close server on exit if we aren't running asynchronously
        if !async 
            terminate()
            # stop any background worker threads
            #Oxygen.Core.StreamUtil.stop(parallelhandler)
        end

        # only reset state on exit if we aren't running asynchronously & are running it interactively 
        if !async && isinteractive()
            resetstate()
        end

    end
end


### Routing Macros ###

"""
    @get(path::String, func::Function)

Used to register a function to a specific endpoint to handle GET requests  
"""
macro get(path, func)
    :(@route ["GET"] $(esc(path)) $(esc(func)))
end

"""
    @post(path::String, func::Function)

Used to register a function to a specific endpoint to handle POST requests
"""
macro post(path, func)
    :(@route ["POST"] $(esc(path)) $(esc(func)))
end

"""
    @put(path::String, func::Function)

Used to register a function to a specific endpoint to handle PUT requests
"""
macro put(path, func)
    :(@route ["PUT"] $(esc(path)) $(esc(func)))
end

"""
    @patch(path::String, func::Function)

Used to register a function to a specific endpoint to handle PATCH requests
"""
macro patch(path, func)
    :(@route ["PATCH"] $(esc(path)) $(esc(func)))
end

"""
    @delete(path::String, func::Function)

Used to register a function to a specific endpoint to handle DELETE requests
"""
macro delete(path, func)
    :(@route ["DELETE"] $(esc(path)) $(esc(func)))
end

"""
    @route(methods::Array{String}, path::String, func::Function)

Used to register a function to a specific endpoint to handle mulitiple request types
"""
macro route(methods, path, func)
    :(route($(esc(methods)), $(esc(path)), $(esc(func))))
end


### Core Routing Functions ###

function route(methods::Vector{String}, path::Union{String,Function}, func::Function)
    for method in methods
        Oxygen.Core.register(CONTEXT[], method, path, func)
    end
end

# This variation supports the do..block syntax
route(func::Function, methods::Vector{String}, path::Union{String,Function}) = route(methods, path, func)

### Core Routing Functions Support for do..end Syntax ###

get(func::Function, path::String)           = route(["GET"], path, func)
get(func::Function, path::Function)         = route(["GET"], path, func)

post(func::Function, path::String)          = route(["POST"], path, func)
post(func::Function, path::Function)        = route(["POST"], path, func)

put(func::Function, path::String)           = route(["PUT"], path, func) 
put(func::Function, path::Function)         = route(["PUT"], path, func) 

patch(func::Function, path::String)         = route(["PATCH"], path, func)
patch(func::Function, path::Function)       = route(["PATCH"], path, func)

delete(func::Function, path::String)        = route(["DELETE"], path, func)
delete(func::Function, path::Function)      = route(["DELETE"], path, func)



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
    loadfile::Union{Function,Nothing}=nothing
) = Oxygen.Core.staticfiles(CONTEXT[], folder, mountdir; headers, loadfile)


dynamicfiles(
    folder::String, 
    mountdir::String="static"; 
    headers::Vector=[], 
    loadfile::Union{Function,Nothing}=nothing
) = Oxygen.Core.dynamicfiles(CONTEXT[], folder, mountdir; headers, loadfile)


internalrequest(req::Oxygen.Request; middleware::Vector=[], metrics::Bool=false, docs::Bool=false, serialize::Bool=true, catch_errors=true, docspath::String="/docs", schemapath="/schema") = Oxygen.Core.internalrequest(CONTEXT[], !isnothing(SERVICE[]) ? Oxygen.Core.history(SERVICE[]) : History(1), req; middleware, metrics, docs, serialize, catch_errors, docspath, schemapath)

function router(prefix::String = ""; 
                tags::Vector{String} = Vector{String}(), 
                middleware::Union{Nothing, Vector} = nothing, 
                interval::Union{Real, Nothing} = nothing,
                cron::Union{String, Nothing} = nothing)

    return Oxygen.Core.AutoDoc.router(CONTEXT[], prefix; tags, middleware, interval, cron)
end


mergeschema(route::String, customschema::Dict) = Oxygen.Core.mergeschema(CONTEXT[].schema, route, customschema)
mergeschema(customschema::Dict) = Oxygen.Core.mergeschema(CONTEXT[].schema, customschema)


"""
    getschema()

Return the current internal schema for this app
"""
function getschema()
    return CONTEXT[].schema
end

# Adding docstrings
@doc (@doc(Oxygen.Core.AutoDoc.router)) router

for method in [:serve, :serveparallel, :staticfiles, :dynamicfiles, :internalrequest, :mergeschema]
    eval(quote
        @doc (@doc(Oxygen.Core.$method)) $method
    end)
end


"""
    setschema(customschema::Dict)

Overwrites the entire internal schema
"""
function setschema(customschema::Dict)

    CONTEXT[] = Context(CONTEXT[]; schema = customschema)

    return
end




"""
    @cron(expression::String, func::Function)

Registers a function with a cron expression. This will extract either the function name 
or the random Id julia assigns to each lambda function. 
"""
macro cron(expression, func)
    quote 
        Oxygen.Core.cron($(CONTEXT[].job_definitions), $(esc(expression)), "$(esc(func))", $(esc(func)))
    end
end


"""
    @cron(expression::String, name::String, func::Function)

This variation Provide another way manually "name" a registered function. This information 
is used by the server on startup to log out all cron jobs.
"""
macro cron(expression, name, func)
    quote 
        Oxygen.Core.cron($(CONTEXT[].job_definitions), $(esc(expression)), "$(esc(name))", $(esc(func)))
    end
end


"""
    clearcronjobs()

Clear any internal reference's to prexisting cron jobs
"""
function clearcronjobs()
    empty!(CONTEXT[].job_definitions)
end


startcronjobs(ctx) = Oxygen.Core.startcronjobs(ctx)

function startcronjobs()
    startcronjobs(CONTEXT[].job_definitions)
end

stopcronjobs(service) = Oxygen.Core.stopcronjobs(service)

function stopcronjobs()
    if !isnothing(SERVICE[])
        Oxygen.Core.stopcronjobs(SERVICE[])
    end
end

stoptasks(service) = Oxygen.Core.stoptasks(service)

function stoptasks()
    if !isnothing(SERVICE[])
        stoptasks(SERVICE[])
    end
end
