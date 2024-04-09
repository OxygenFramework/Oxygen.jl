module Core

using HTTP
using HTTP: Router
using Sockets 
using JSON3
using Base 
using Dates
using Reexport
using RelocatableFolders
using DataStructures: CircularDeque
import Base.Threads: lock

include("types.jl");        @reexport using .Types 
include("constants.jl");    @reexport using .Constants
include("handlers.jl");     @reexport using .Handlers
include("context.jl");      @reexport using .AppContext
include("util.jl");         @reexport using .Util
include("cron.jl");         @reexport using .Cron
include("repeattasks.jl");  @reexport using .RepeatTasks
include("autodoc.jl");      @reexport using .AutoDoc
include("metrics.jl");      @reexport using .Metrics
include("reflection.jl");   @reexport using .Reflection

export  start, serve, serveparallel, terminate, 
        internalrequest, staticfiles, dynamicfiles
                        
oxygen_title = raw"""
   ____                            
  / __ \_  ____  ______ ____  ____ 
 / / / / |/_/ / / / __ `/ _ \/ __ \
/ /_/ />  </ /_/ / /_/ /  __/ / / /
\____/_/|_|\__, /\__, /\___/_/ /_/ 
          /____//____/   

"""

function serverwelcome(host::String, port::Int, docs::Bool, metrics::Bool, parallel::Bool, docspath::String)
    printstyled(oxygen_title, color = :blue, bold = true)
    @info "📦 Version 1.5.4 (2024-04-01)"
    @info "✅ Started server: http://$host:$port" 
    docs     && @info "📖 Documentation: http://$host:$port$docspath"
    metrics  && @info "📊 Metrics: http://$host:$port$docspath/metrics"
    parallel && @info "🚀 Running in parallel mode with $(Threads.nthreads()) threads"
end


"""
    serve(; middleware::Vector=[], handler=stream_handler, host="127.0.0.1", port=8080, serialize=true, async=false, catch_errors=true, docs=true, metrics=true, kwargs...)

Start the webserver with your own custom request handler
"""
function serve(ctx::Context; 
    middleware  = [],
    handler     = stream_handler,
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
    kwargs...) :: Server

    # overwrite docs & schema paths
    ctx.docs.docspath[] = docs_path
    ctx.docs.schemapath[] = schema_path

    # intitialize documenation router (used by docs and metrics)
    ctx.docs.router[] = Router()

    # compose our middleware ahead of time (so it only has to be built up once)
    configured_middelware = setupmiddleware(ctx; middleware, serialize, catch_errors, docs, metrics, show_errors)

    # setup the primary stream handler function (can be customized by the caller)
    handle_stream = handler(configured_middelware)

    # The cleanup of resources are put at the topmost level in `methods.jl`
    return startserver(ctx; host, port, show_banner, docs, metrics, kwargs, async, start=(kwargs) -> 
        HTTP.serve!(handle_stream, host, port; kwargs...))
end


"""
    serveparallel(; middleware::Vector=[], handler=stream_handler, host="127.0.0.1", port=8080, serialize=true, async=false, catch_errors=true, docs=true, metrics=true, kwargs...)

Starts the webserver in streaming mode with your own custom request handler and spawns n - 1 worker 
threads to process individual requests. A Channel is used to schedule individual requests in FIFO order. 
Requests in the channel are then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(ctx::Context; 
    middleware  = [], 
    handler     = stream_handler, 
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
    kwargs...) :: Server

    if Threads.nthreads() <= 1
        @warn "serveparallel() only has 1 thread available to use, try launching julia like this: \"julia -t auto\" to leverage multiple threads"
    end

    if haskey(kwargs, :queuesize)
        @warn "Deprecated: The `queuesize` parameter is no longer used / supported in serveparallel()"
    end

    # overwrite docs & schema paths
    ctx.docs.docspath[] = docs_path
    ctx.docs.schemapath[] = schema_path

    # intitialize documenation router (used by docs and metrics)
    ctx.docs.router[] = Router()

    # compose our middleware ahead of time (so it only has to be built up once)
    configured_middelware = setupmiddleware(ctx; middleware, serialize, catch_errors, docs, metrics, show_errors)

    # setup the primary stream handler function (can be customized by the caller)
    handle_stream = handler(configured_middelware) |> parallel_stream_handler 

    return startserver(ctx; host, port, show_banner, docs, metrics, parallel=true, async, kwargs, start=(kwargs) -> 
        HTTP.serve!(handle_stream, host, port; kwargs...))
end


"""
    terminate(ctx)

stops the webserver immediately
"""
function terminate(context::Context)
    if isopen(context.service)
        # stop background cron jobs
        stopcronjobs(context.cron)
        clearcronjobs(context.cron)

        # stop repeating tasks
        stoptasks(context.tasks) 
        cleartasks(context.tasks)

        # stop server
        close(context.service)
    end
end


"""
Register all cron jobs defined through our router() HOF
"""
function registercronjobs(ctx::Context)
    for job in ctx.cron.job_definitions
        path, httpmethod, expression = job.path, job.httpmethod, job.expression
        cron(ctx.cron.registered_jobs, expression, path, () -> internalrequest(ctx, HTTP.Request(httpmethod, path)))
    end
end

"""
Register all repeat tasks defined through our router() HOF
"""
function registertasks(ctx::Context)
    for task_def in ctx.tasks.task_definitions
        path, httpmethod, interval = task_def.path, task_def.httpmethod, task_def.interval
        task(ctx.tasks.registered_tasks, interval, path, () -> internalrequest(ctx, HTTP.Request(httpmethod, path)))
    end
end

"""
    decorate_request(ip::IPAddr)

This function can be used to add additional usefull metadata to the incoming 
request context dictionary. At the moment, it just inserts the caller's ip address
"""
function decorate_request(ip::IPAddr, stream::HTTP.Stream)
    return function(handle)
        return function(req::HTTP.Request)
            req.context[:ip] = ip
            req.context[:stream] = stream
            handle(req)
        end
    end
end

"""
This is our root stream handler used in both serve() and serveparallel().
This function determines how we handle all incoming requests
"""

function stream_handler(middleware::Function)
    return function (stream::HTTP.Stream)
        # extract the caller's ip address
        ip, _ = Sockets.getpeername(stream)
        # build up a streamhandler to handle our incoming requests
        handle_stream = HTTP.streamhandler(middleware |> decorate_request(ip, stream))
        # handle the incoming request
        return handle_stream(stream)
    end
end


"""
    parallel_stream_handler(handle_stream::Function)

This function uses `Threads.@spawn` to schedule a new task on any available thread. 
Inside this task, `@async` is used for cooperative multitasking, allowing the task to yield during I/O operations. 
"""
function parallel_stream_handler(handle_stream::Function)
    function(stream::HTTP.Stream)
        task = Threads.@spawn begin 
            handle = @async handle_stream(stream)  
            wait(handle)
        end
        wait(task)
    end
end


"""
Compose the user & internally defined middleware functions together. Practically, this allows
users to 'chain' middleware functions like `serve(handler1, handler2, handler3)` when starting their 
application and have them execute in the order they were passed (left to right) for each incoming request
"""
function setupmiddleware(ctx::Context; middleware::Vector=[], docs::Bool=true, metrics::Bool=true, serialize::Bool=true, catch_errors::Bool=true, show_errors=true) :: Function

    # determine if we have any special router or route-specific middleware
    custom_middleware = hasmiddleware(ctx.service.custommiddleware) ? [compose(ctx.service.router, middleware, ctx.service.custommiddleware)] : reverse(middleware)

    # Docs middleware should only be available at runtime when serve() or serveparallel is called
    docs_middleware = docs && !isnothing(ctx.docs.router[]) ? [DocsMiddleware(ctx.docs.router[], ctx.docs.docspath[])] : []

    # check if we should use our default serialization middleware function
    serializer = serialize ? [DefaultSerializer(catch_errors; show_errors)] : []

    # check if we need to track metrics
    collect_metrics = metrics ? [MetricsMiddleware(ctx.service, metrics)] : []

    # combine all our middleware functions
    return reduce(|>, [
        ctx.service.router,
        serializer...,
        custom_middleware...,
        collect_metrics...,
        docs_middleware...,
    ])    
end


"""
Internal helper function to launch the server in a consistent way
"""
function startserver(ctx::Context; host, port, show_banner=false, docs=false, metrics=false, parallel=false, async=false, kwargs, start) :: Server

    show_banner && serverwelcome(host, port, docs, metrics, parallel, ctx.docs.docspath[])

    docs && setupdocs(ctx)
    metrics && setupmetrics(ctx)

    # start the HTTP server
    ctx.service.server[] = start(preprocesskwargs(kwargs))

    # Register & Start all repeat tasks
    registertasks(ctx)
    starttasks(ctx.tasks)

    # Register & Start all cron jobs
    registercronjobs(ctx)
    startcronjobs(ctx.cron)

    if !async     
        try
            wait(ctx.service)
        catch error
            !isa(error, InterruptException) && @error "ERROR: " exception=(error, catch_backtrace())
        finally 
            println() # this pushes the "[ Info: Server on 127.0.0.1:8080 closing" to the next line
        end
    end

    return ctx.service.server[]
end


"""
Used to overwrite defaults to any incoming keyword arguments
"""
function preprocesskwargs(kwargs)
    kwargs_dict = Dict{Symbol, Any}(kwargs)

    # always set to streaming mode (regardless of what was passed)
    kwargs_dict[:stream] = true

    # user passed no loggin preferences - use defualt logging format 
    if isempty(kwargs_dict) || !haskey(kwargs_dict, :access_log)
        kwargs_dict[:access_log] = logfmt"$time_iso8601 - $remote_addr:$remote_port - \"$request\" $status"
    end  

    return kwargs_dict
end


"""
    internalrequest(req::HTTP.Request; middleware::Vector=[], serialize::Bool=true, catch_errors::Bool=true)

Directly call one of our other endpoints registered with the router, using your own middleware
and bypassing any globally defined middleware
"""
function internalrequest(ctx::Context, req::HTTP.Request; middleware::Vector=[], metrics::Bool=false, serialize::Bool=true, catch_errors=true) :: HTTP.Response
    req.context[:ip] = "INTERNAL" # label internal requests
    return req |> setupmiddleware(ctx; middleware, metrics, serialize, catch_errors)
end


function DocsMiddleware(docsrouter::Router, docspath::String)
    return function(handle)
        return function(req::HTTP.Request)
            if startswith(req.target, docspath)
                response = docsrouter(req)
            else
                response = handle(req)
            end
            format_response!(req, response)               
            return req.response
        end
    end
end


"""
Create a default serializer function that handles HTTP requests and formats the responses.
"""
function DefaultSerializer(catch_errors::Bool; show_errors::Bool)
    return function(handle)
        return function(req::HTTP.Request)
            return handlerequest(catch_errors; show_errors) do 
                response = handle(req)
                format_response!(req, response)
                return req.response
            end
        end
    end
end

function MetricsMiddleware(service::Service, catch_errors::Bool) 
    return function(handler)
        return function(req::HTTP.Request)
            return handlerequest(catch_errors) do 
                start_time = time()
                # Handle the request
                response = handler(req)
                # Log response time
                response_time = (time() - start_time) * 1000
                # Make sure we update the History object in a thread-safe way
                lock(service.history_lock) do 
                    if response.status == 200
                        push_history(service.history, HTTPTransaction(
                            string(req.context[:ip]),
                            string(req.target),
                            now(UTC),
                            response_time,
                            true,
                            response.status,
                            nothing
                        ))
                    else 
                        push_history(service.history, HTTPTransaction(
                            string(req.context[:ip]),
                            string(req.target),
                            now(UTC),
                            response_time,
                            false,
                            response.status,
                            text(response)
                        ))
                    end
                end
                return response
            end
        end
    end
end


function parse_route(httpmethod::String, route::Union{String,Function}) :: String

    # check if path is a callable function (that means it's a router higher-order-function)
    if isa(route, Function)

        # This is true when the user passes the router() directly to the path.
        # We call the generated function without args so it uses the default args 
        # from the parent function.
        if countargs(route) == 1
            route = route()
        end

        # If it's still a function, then that means this is from the 3rd inner function 
        # defined in the createrouter() function.
        if countargs(route) == 2
            route = route(httpmethod)
        end
    end

    # if the route is still a function, then it's from the  3rd inner function 
    # defined in the createrouter() function when the 'router()' function is passed directly.
    if isa(route, Function)
        route = route(httpmethod)
    end    

    !isa(route, String) && throw("The `route` parameter is not a String, but is instead a: $(typeof(route))")
      
    return route
end


function parse_func_params(route::String, func::Function)
    
    variableRegex = r"{[a-zA-Z0-9_]+}"
    hasBraces = r"({)|(})"
    
    # track which index the params are located in
    positions = []
    for (index, value) in enumerate(HTTP.URIs.splitpath(route)) 
        if contains(value, hasBraces)
            # extract the variable name
            variable = replace(value, hasBraces => "") |> x -> split(x, ":") |> first        
            push!(positions, (index, variable))
        end
    end

    method = first(methods(func))
    numfields = method.nargs

    # extract the function handler's field names & types 
    fields = [x for x in fieldtypes(method.sig)]
    func_param_names = [String(param) for param in Base.method_argnames(method)[3:end]]
    func_param_types = splice!(Array(fields), 3:numfields)

    # each tuple tracks where the param is refereced (variable, function index, path index)
    param_positions::Array{Tuple{String, Int, Int}} = []

    # ensure the function params are present inside the path params 
    for (_, path_param) in positions
        hasparam = false
        for (_, func_param) in enumerate(func_param_names)
            if func_param == path_param 
                hasparam = true
                break
            end
        end
        if !hasparam
            throw("Your request handler is missing a parameter: '$path_param' defined in this route: $route")
        end
    end

    # ensure the path params are present inside the function params 
    for (func_index, func_param) in enumerate(func_param_names)
        matched = nothing
        for (path_index, path_param) in positions
            if func_param == path_param 
                matched = (func_param, func_index, path_index)
                break
            end
        end
        if matched === nothing
            throw("Your path is missing a parameter: '$func_param' which needs to be added to this route: $route")
        else 
            push!(param_positions, matched)
        end
    end

    # determine if we have parameters defined in our path
    hasPathParams = contains(route, variableRegex) # Can this be replaced with !isempty(func_param_names)

    return hasPathParams, func_param_names, func_param_types
end


"""
    register(ctx::Context, httpmethod::String, route::String, func::Function)

Register a request handler function with a path to the ROUTER
"""
function register(ctx::Context, httpmethod::String, route::Union{String,Function}, func::Function)
    # Parse & validate path parameters
    route = parse_route(httpmethod, route)
    hasPathParams, func_param_names, func_param_types = parse_func_params(route, func)
    path_params = [param for param in zip(func_param_names, func_param_types)]

    # Register the route schema with out autodocs module
    registerschema(ctx.docs, route, httpmethod, path_params, Base.return_types(func))

    # Register the route with the router
    registerhandler(ctx.service.router, httpmethod, route, func, hasPathParams, (func_param_names, func_param_types, path_params))
end


"""
This alternaive registers a route wihout generating any documentation for it. Used primarily for internal routes like 
docs and metrics
"""
function register(router::Router, httpmethod::String, route::Union{String,Function}, func::Function)
    # Parse & validate path parameters
    route = parse_route(httpmethod, route)
    hasPathParams, func_param_names, func_param_types = parse_func_params(route, func)
    path_params = [param for param in zip(func_param_names, func_param_types)]

    # Register the route with the router
    registerhandler(router, httpmethod, route, func, hasPathParams, (func_param_names, func_param_types, path_params))
end

function registerhandler(router::Router, httpmethod::String, route::String, func::Function, hasPathParams::Bool, path_params)
    func_param_names, func_param_types, path_params = path_params
    func_map = Dict(name => type for (name, type) in zip(func_param_names, func_param_types))

    # Get information about the function's arguments
    method = first(methods(func))
    no_args = method.nargs == 1
    has_req_kwarg = :request in Base.kwarg_decl(method)

    # Generate the function handler based on the input types
    arg_type = first_arg_type(method, httpmethod)
    func_handle = select_handler(arg_type, has_req_kwarg, hasPathParams; no_args=no_args)

    # Wrap the generated handler so it can be registered with the router
    if hasPathParams
        handle = function(req::HTTP.Request)
            params = HTTP.getparams(req)
            pathParams = [parseparam(func_map[name], params[name]) for name in func_param_names]
            func_handle(req, func; pathParams=pathParams)
        end
    else
        handle = function(req::HTTP.Request)
            func_handle(req, func)
        end
    end

    # Use method aliases for special methods
    resolved_httpmethod = get(METHOD_ALIASES, httpmethod, httpmethod)
    HTTP.register!(router, resolved_httpmethod, route, handle)
end

function setupdocs(ctx::Context)
    setupdocs(ctx.docs.router[], ctx.docs.schema, ctx.docs.docspath[], ctx.docs.schemapath[])
end

# add the swagger and swagger/schema routes 
function setupdocs(router::Router, schema::Dict, docspath::String, schemapath::String)
    full_schema = "$docspath$schemapath"
    register(router, "GET", "$docspath", () -> swaggerhtml(full_schema, docspath))
    register(router, "GET", "$docspath/swagger", () -> swaggerhtml(full_schema, docspath))
    register(router, "GET", "$docspath/redoc", () -> redochtml(full_schema, docspath))
    register(router, "GET", full_schema, () -> schema)
end

function setupmetrics(context::Context)
    setupmetrics(context.docs.router[], context.service.history, context.docs.docspath[], context.service.history_lock)
end

# add the swagger and swagger/schema routes 
function setupmetrics(router::Router, history::History, docspath::String, history_lock::ReentrantLock)

    # This allows us to customize the path to the metrics dashboard
    function loadfile(filepath) :: String
        content = readfile(filepath)
        # only replace content if it's in a generated file
        ext = lowercase(last(splitext(filepath)))
        if ext in [".html", ".css", ".js"]
            return replace(content, "/df9a0d86-3283-4920-82dc-4555fc0d1d8b/" => "$docspath/metrics/")
        else
            return content
        end
    end

    staticfiles(router, "$DATA_PATH/dashboard", "$docspath/metrics"; loadfile=loadfile)

    # Create a thread-safe copy of the history object and it's internal data
    function safe_get_transactions(history::History) :: Vector{HTTPTransaction}
        transactions = []
        lock(history_lock) do
            transactions = collect(history)
        end
        return transactions
    end
    
    function metrics(req::HTTP.Request, window::Nullable{Int}, latest::Nullable{DateTime})

        # create a threadsafe copy of the current transactions in our history object
        transactions = safe_get_transactions(history)
        
        # Figure out how far back to read from the history object
        window_value = !isnothing(window) && window > 0 ? Minute(window) : nothing
        lower_bound = !isnothing(latest) ? latest : window_value
        
        return Dict(
            "server"     => server_metrics(transactions, nothing),
            "endpoints"  => all_endpoint_metrics(transactions, nothing),
            "errors"     => error_distribution(transactions, nothing),
            "avg_latency_per_second" => avg_latency_per_unit(transactions, Second, lower_bound)   |> prepare_timeseries_data(),
            "requests_per_second"    => requests_per_unit(transactions, Second, lower_bound)      |> prepare_timeseries_data(),
            "avg_latency_per_minute" => avg_latency_per_unit(transactions, Minute, lower_bound)   |> prepare_timeseries_data(),
            "requests_per_minute"    => requests_per_unit(transactions, Minute, lower_bound)      |> prepare_timeseries_data()
        )
        
    end

    register(router, GET, "$docspath/metrics/data/{window}/{latest}", metrics)
end


"""
    staticfiles(folder::String, mountdir::String; headers::Vector{Pair{String,String}}=[], loadfile::Union{Function,Nothing}=nothing)

Mount all files inside the /static folder (or user defined mount point). 
The `headers` array will get applied to all mounted files
"""
function staticfiles(router::HTTP.Router,
        folder::String, 
        mountdir::String="static"; 
        headers::Vector=[], 
        loadfile::Nullable{Function}=nothing
    )
    # remove the leading slash 
    if first(mountdir) == '/'
        mountdir = mountdir[2:end]
    end
    function addroute(currentroute, filepath)
        resp = file(filepath; loadfile=loadfile, headers=headers)
        register(router, GET, currentroute, () -> resp)
    end
    mountfolder(folder, mountdir, addroute)  
end


"""
    dynamicfiles(folder::String, mountdir::String; headers::Vector{Pair{String,String}}=[], loadfile::Union{Function,Nothing}=nothing)

Mount all files inside the /static folder (or user defined mount point), 
but files are re-read on each request. The `headers` array will get applied to all mounted files
"""
function dynamicfiles(router::Router,
        folder::String, 
        mountdir::String="static"; 
        headers::Vector=[], 
        loadfile::Nullable{Function}=nothing
    )
    # remove the leading slash 
    if first(mountdir) == '/'
        mountdir = mountdir[2:end]
    end
    function addroute(currentroute, filepath)
        register(router, GET, currentroute, () -> file(filepath; loadfile=loadfile, headers=headers))
    end
    mountfolder(folder, mountdir, addroute)    
end

end
