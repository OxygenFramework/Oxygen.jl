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

include("types.jl");        @reexport using .Types 
include("constants.jl");    @reexport using .Constants
include("context.jl");      @reexport using .AppContext
include("util.jl");         @reexport using .Util
include("cron.jl");         @reexport using .Cron
include("streamutil.jl");   @reexport using .StreamUtil
include("autodoc.jl");      @reexport using .AutoDoc
include("metrics.jl");      @reexport using .Metrics

export  staticfiles, dynamicfiles,
        start, serve, serveparallel, terminate, internalrequest,
        resetstate, starttasks, stoptasks, Runtime, Service, history


struct TasksContext
    repeattasks::Vector
end

struct TasksRuntime
    timers::Vector{Timer}
end

#struct Runtime
#     history::History
#     cron::CronRuntime
#     tasks::TasksRuntime
# end

struct Service
    context::Context # an immutable constant in this struct
    history::History
    cron::CronRuntime
    tasks::TasksRuntime
    server::HTTP.Server
end


Base.close(service::Service) = close(service.server)
Base.wait(service::Service) = wait(service.server)


history(service::Service) = service.history

Cron.stopcronjobs(service::Service) = stopcronjobs(service.cron)
#Cron.stopcronjobs(runtime::Runtime) = stopcronjobs(runtime.cron)

stoptasks(service::Service) = stoptasks(service.tasks)
#stoptasks(runtime::Runtime) = stoptasks(runtime.tasks)



"""
    terminate(ctx)

stops the webserver immediately
"""
function terminate(service::Service)
    if isopen(service.server)
        # stop background cron jobs
        #Oxygen.Core.stopcronjobs()
        stopcronjobs(service)
        # stop background tasks
        #Oxygen.Core.stoptasks()
        stoptasks(service)
        # stop server
        close(service)
    end
end



oxygen_title = raw"""
   ____                            
  / __ \_  ____  ______ ____  ____ 
 / / / / |/_/ / / / __ `/ _ \/ __ \
/ /_/ />  </ /_/ / /_/ /  __/ / / /
\____/_/|_|\__, /\__, /\___/_/ /_/ 
          /____//____/   

"""

function serverwelcome(host::String, port::Int, docs::Bool, metrics::Bool, docspath::String)
    printstyled(oxygen_title, color = :blue, bold = true)
    @info "📦 Version 1.4.8 (2024-02-01)"
    @info "✅ Started server: http://$host:$port" 
    docs    && @info "📖 Documentation: http://$host:$port$docspath"
    metrics && @info "📊 Metrics: http://$host:$port$docspath/metrics"
end


"""
    starttasks()

Start all background repeat tasks
"""
function starttasks(ctx::Context, history::History) :: TasksRuntime

    rt = TasksRuntime([])

    # exit function early if no tasks are register
    if isempty(ctx.repeattasks)
        return rt
    end

    println()
    printstyled("[ Starting $(length(ctx.repeattasks)) Repeat Task(s)\n", color = :magenta, bold = true)  
    
    for task in ctx.repeattasks
        path, httpmethod, interval = task
        message = "method: $httpmethod, path: $path, inverval: $interval seconds"
        printstyled("[ Task: ", color = :magenta, bold = true)  
        println(message)
        action = (timer) -> internalrequest(ctx, history, HTTP.Request(httpmethod, path))
        timer = Timer(action, 0, interval=interval)
        push!(rt.timers, timer)   
    end

    return rt
end 


"""
Register all cron jobs 
"""
function registercronjobs(ctx::Context, history::History) # Needs to be refactored
    #for job in getcronjobs()
    for job in ctx.cronjobs
        path, httpmethod, expression = job

        cron(ctx.job_definitions, expression, path, () -> internalrequest(ctx, history, HTTP.Request(httpmethod, path)))
    end
end 

"""
    stoptasks()

Stop all background repeat tasks
"""
function stoptasks(rt::TasksRuntime)
    for timer in rt.timers
        if isopen(timer)
            close(timer)
        end
    end
    empty!(rt.timers)
end

"""
    decorate_request(ip::IPAddr)

This function can be used to add additional usefull metadata to the incoming 
request context dictionary. At the moment, it just inserts the caller's ip address
"""
function decorate_request(ip::IPAddr)
    return function(handle)
        return function(req::HTTP.Request)
            req.context[:ip] = ip
            handle(req)
        end
    end
end

"""
This function determines how we handle the incoming request 
"""
function stream_handler(middleware::Function)
    return function (stream::HTTP.Stream)
        # extract the caller's ip address
        ip, _ = Sockets.getpeername(stream)
        # build up a streamhandler to handle our incoming requests
        handle_stream = HTTP.streamhandler(middleware |> decorate_request(ip))
        # handle the incoming request
        return handle_stream(stream)
    end
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
    docspath    = "/docs",
    schemapath  = "/schema",
    kwargs...)

    history = History(1_000_000)

    # compose our middleware ahead of time (so it only has to be built up once)
    configured_middelware = setupmiddleware(ctx, history; middleware, serialize, catch_errors, docs, metrics, show_errors, docspath, schemapath)

    # The cleanup of resources are put at the topmost level in `methods.jl`

    return startserver(ctx, history, host, port, docs, metrics, kwargs, async, (kwargs) ->  
            HTTP.serve!(handler(configured_middelware), host, port; kwargs...); docspath, schemapath)
end


"""
    serveparallel(; middleware::Vector=[], handler=stream_handler, host="127.0.0.1", port=8080, queuesize=1024, serialize=true, async=false, catch_errors=true, docs=true, metrics=true, kwargs...)

Starts the webserver in streaming mode with your own custom request handler and spawns n - 1 worker 
threads to process individual requests. A Channel is used to schedule individual requests in FIFO order. 
Requests in the channel are then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(ctx::Context; 
    middleware  = [], 
    handler     = stream_handler, 
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

    parallelhandler = StreamUtil.Handler() 
    history = History(1_000_000)
    
    try
        # compose our middleware ahead of time (so it only has to be built up once)
        configured_middelware = setupmiddleware(ctx, history; middleware, serialize, catch_errors, docs, metrics, show_errors, docspath, schemapath)

        return startserver(ctx, history, host, port, docs, metrics, kwargs, async, (kwargs) -> 
            StreamUtil.start(_handler, handler(configured_middelware); host=host, port=port, queuesize=queuesize, kwargs...);
                           docspath, schemapath)
    finally
        StreamUtil.stop(parallelhandler)
    end
end


"""
Compose the user & internally defined middleware functions together. Practically, this allows
users to 'chain' middleware functions like `serve(handler1, handler2, handler3)` when starting their 
application and have them execute in the order they were passed (left to right) for each incoming request
"""
function setupmiddleware(ctx::Context, history::History; middleware::Vector=[], docs::Bool=false, metrics::Bool=true, serialize::Bool=true, catch_errors::Bool=true, show_errors=true, docspath = "/docs", schemapath = "/schema") :: Function

    # determine if we have any special router or route-specific middleware
    custom_middleware = hasmiddleware(ctx.custommiddleware) ? [compose(ctx.router, middleware, ctx.custommiddleware)] : reverse(middleware)

    # Note that this will make internalrequest slow which
    # calls setupmiddleware uppon every request. 
    if docs || metrics
        router = Router()

        docs && setupswagger(router, ctx.schema, docspath, schemapath)
        metrics && setupmetrics(router, history, docspath)

        docs_middleware = [DocsMiddleware(router, docspath)]
    else
        docs_middleware = []
    end

    # check if we should use our default serialization middleware function
    serializer = serialize ? [DefaultSerializer(catch_errors; show_errors)] : []

    # check if we need to track metrics
    collect_metrics = metrics ? [MetricsMiddleware(history, metrics, docspath)] : []

    # combine all our middleware functions
    return reduce(|>, [
        ctx.router,
        docs_middleware...,
        serializer...,
        custom_middleware...,
        collect_metrics...,
    ])    
end


"""
Internal helper function to launch the server in a consistent way
"""
function startserver(ctx::Context, history::History, host, port, docs, metrics, kwargs, async, start; docspath="/docs", schemapath="/schema")

    serverwelcome(host, port, docs, metrics, docspath)

    server = start(preprocesskwargs(kwargs)) # How does this one work!
    rt_tasks = starttasks(ctx, history)

    # NOTE FOR A FUTURE REFACTOR
    # `registercronjobs` function afects `job_definitions` from previoulsy registered `cronjobs`. 
    # The `cronjobs` are created with `router`. Instead it should be returned as value there 
    # in a struct which then could be passed down to register function thus this registration
    # would not need to be done at runtime. This may also cause bugs when server is restarted.

    registercronjobs(ctx, history) 
    rt_cron = startcronjobs(ctx.job_definitions)


    service = Service(ctx, history, rt_cron, rt_tasks, server)

    if !async     
        try 
            wait(server)
        catch 
            println() # this pushes the "[ Info: Server on 127.0.0.1:8080 closing" to the next line
        end
    end

    return service
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
function internalrequest(ctx::Context, history::History, req::HTTP.Request; middleware::Vector=[], metrics::Bool=false, docs::Bool=false, serialize::Bool=true, catch_errors=true, docspath::String="/docs", schemapath="/schema") :: HTTP.Response
    req.context[:ip] = "INTERNAL" # label internal requests
    return req |> setupmiddleware(ctx, history; middleware, metrics, docs, serialize, catch_errors, docspath, schemapath)
end


function DocsMiddleware(router::Router, docspath::String)
    return function(handle)
        return function(req::HTTP.Request)
            if startswith(req.target, docspath)
                return router(req)
            else
                return handle(req)
            end
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

function MetricsMiddleware(history::History, catch_errors::Bool, docspath::String) 
    return function(handler)
        return function(req::HTTP.Request)
            return handlerequest(catch_errors) do 
                
                # Don't capture metrics on the documenation internals
                if contains(req.target, docspath)
                    return handler(req)
                end

                start_time = time()
                try
                    # Handle the request
                    response = handler(req)
                    # Log response time
                    response_time = (time() - start_time) * 1000
                    if response.status == 200
                        push_history(history, HTTPTransaction(
                            string(req.context[:ip]),
                            string(req.target),
                            now(UTC),
                            response_time,
                            true,
                            response.status,
                            nothing
                        ))
                    else 
                        push_history(history, HTTPTransaction(
                            string(req.context[:ip]),
                            string(req.target),
                            now(UTC),
                            response_time,
                            false,
                            response.status,
                            text(response)
                        ))
                    end

                    # Return the response
                    return response
                catch e          
                    response_time = (time() - start_time) * 1000

                    # Log the error
                    push_history(history, HTTPTransaction(
                        string(req.context[:ip]),
                        string(req.target),
                        now(UTC),
                        response_time,
                        false,
                        500,
                        string(typeof(e))
                    ))

                    # let our caller figure out if they want to handle the error or not
                    rethrow(e)
                end
            end
        end
    end
end

parse_route(httpmethod::String, route::String) = route

function parse_route(httpmethod::String, route::Function)

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
    # defined in the createrouter()function when the 'router()' function is passed directly.
    if isa(route, Function)
        route = route(httpmethod)
    end    

    if !isa(route, String)
        throw("The `route` parameter is not a String, but is instead a: $(typeof(route))")
    end  

    return route
end


function parse_func_params(httpmethod::String, route::String, func::Function)
    
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
#function register(ctx::Context, httpmethod::String, route::Union{String,Function}, func::Function)
function register(ctx::Context, httpmethod::String, route::Union{String,Function}, func::Function)

    route = parse_route(httpmethod, route)
    hasPathParams, func_param_names, func_param_types = parse_func_params(httpmethod, route, func)

    registerschema(ctx, route, httpmethod, zip(func_param_names, func_param_types), Base.return_types(func))

    register(ctx.router, httpmethod, route, func, (hasPathParams, func_param_names, func_param_types))
end

function register(router::Router, httpmethod::String, route::Union{String,Function}, func::Function)

    route = parse_route(httpmethod, route)
    hasPathParams, func_param_names, func_param_types = parse_func_params(httpmethod, route, func)

    register(router, httpmethod, route, func, (hasPathParams, func_param_names, func_param_types))
end

function register(router::Router, httpmethod::String, route::String, func::Function, func_params)

    (hasPathParams, func_param_names, func_param_types) = func_params

    # create a map of paramter name to type definition
    func_map = Dict(name => type for (name, type) in zip(func_param_names, func_param_types))

    method = first(methods(func))
    numfields = method.nargs

    # case 1.) The request handler is an anonymous function (don't parse out path params)
    if numfields <= 1
        handle = function (req)
            func()
        end   
        # case 2.) This route has path params, so we need to parse parameters and pass them to the request handler
    elseif hasPathParams && numfields > 2
        handle = function (req) 
            # get all path parameters
            params = HTTP.getparams(req)
            # convert params to their designated type (if applicable)
            pathParams = [parseparam(func_map[name], params[name]) for name in func_param_names]   
            # pass all parameters to handler in the correct order 
            func(req, pathParams...)
        end
        # case 3.) This function should only get passed the request object
    else 
        handle = function (req) 
            func(req)
        end
    end

    HTTP.register!(router, httpmethod, route, handle)
end


# add the swagger and swagger/schema routes 
function setupswagger(router::Router, schema::Dict, docspath::String, schemapath::String)

    register(router, "GET", "$docspath", req -> swaggerhtml("$docspath$schemapath"))

    register(router, "GET", "$docspath/swagger", req -> swaggerhtml("$docspath$schemapath"))
    
    register(router, "GET", "$docspath/redoc", req -> redochtml("$docspath$schemapath"))

    register(router, "GET", "$docspath$schemapath", req -> schema)
    
    #end

end

# add the swagger and swagger/schema routes 
function setupmetrics(router::Router, history::History, docspath::String)

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
    
    function metrics(req, window::Union{Int, Nothing}, latest::Union{DateTime, Nothing})
        lower_bound = !isnothing(window) && window > 0 ? Minute(window) : nothing

        if !isnothing(latest)
            lower_bound = latest
        end

        return Dict(
           "server" => server_metrics(history, nothing),
           "endpoints" => all_endpoint_metrics(history, nothing),
           "errors" => error_distribution(history, nothing),
           "avg_latency_per_second" =>  avg_latency_per_unit(history, Second, lower_bound) |> prepare_timeseries_data(),
           "requests_per_second" =>  requests_per_unit(history, Second, lower_bound) |> prepare_timeseries_data(),
           "avg_latency_per_minute" => avg_latency_per_unit(history, Minute, lower_bound)  |> prepare_timeseries_data(),
           "requests_per_minute" => requests_per_unit(history, Minute, lower_bound)  |>  prepare_timeseries_data()
        )
    end

    register(router, "GET", "$docspath/metrics/data/{window}/{latest}", metrics)
end


"""
    staticfiles(folder::String, mountdir::String; headers::Vector{Pair{String,String}}=[], loadfile::Union{Function,Nothing}=nothing)

Mount all files inside the /static folder (or user defined mount point). 
The `headers` array will get applied to all mounted files
"""
function staticfiles(router::Router,
        folder::String, 
        mountdir::String="static"; 
        headers::Vector=[], 
        loadfile::Union{Function,Nothing}=nothing
    )

    # remove the leading slash 
    if first(mountdir) == '/'
        mountdir = mountdir[2:end]
    end

    function addroute(currentroute, filepath)
        # calculate the entire response once on load
        resp = file(filepath; loadfile=loadfile, headers=headers)
        register(router, "GET", currentroute, req -> resp)
    end
    mountfolder(folder, mountdir, addroute)
end

function staticfiles(ctx::Context, folder::String, mountdir::String="static"; 
                     headers::Vector=[], loadfile::Union{Function,Nothing}=nothing)

    # remove the leading slash 
    if first(mountdir) == '/'
        mountdir = mountdir[2:end]
    end

    staticfiles(ctx.router, folder, mountdir; headers, loadfile)
    registermountedfolder(ctx.mountedfolders, mountdir) 
end



"""
    dynamicfiles(folder::String, mountdir::String; headers::Vector{Pair{String,String}}=[], loadfile::Union{Function,Nothing}=nothing)

Mount all files inside the /static folder (or user defined mount point), 
but files are re-read on each request. The `headers` array will get applied to all mounted files
"""
function dynamicfiles(ctx::Context, #TODO: Make the same refactor as with staticfiles
        folder::String, 
        mountdir::String="static"; 
        headers::Vector=[], 
        loadfile::Union{Function,Nothing}=nothing
    )
    # remove the leading slash 
    if first(mountdir) == '/'
        mountdir = mountdir[2:end]
    end
    registermountedfolder(ctx.mountedfolders, mountdir)
    function addroute(currentroute, filepath)

        register(ctx, "GET", currentroute, req -> file(filepath; loadfile=loadfile, headers=headers))

    end
    mountfolder(folder, mountdir, addroute)    
end


end
