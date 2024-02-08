module Core

using HTTP
using HTTP: Router

using Sockets 
using JSON3
using Base 
using Dates
using Suppressor
using Reexport
using RelocatableFolders

using DataStructures: CircularDeque


include("util.jl");         @reexport using .Util
include("streamutil.jl");   @reexport using .StreamUtil
include("autodoc.jl");      @reexport using .AutoDoc
include("metrics.jl");      @reexport using .Metrics

using .Metrics: HTTPTransaction
using .StreamUtil: Handler
using .AutoDoc: TaggedRoute

export  @cron, 
        staticfiles, dynamicfiles,
        start, serve, serveparallel, terminate, internalrequest,
        resetstate, starttasks, stoptasks


global const timers = Ref{Vector{Timer}}([]) # CRON STATE


# Generate a reliable path to our internal data folder that works when the 
# package is used with PackageCompiler.jl
global const DATA_PATH = @path abspath(joinpath(@__DIR__, "..", "data"))

oxygen_title = raw"""
   ____                            
  / __ \_  ____  ______ ____  ____ 
 / / / / |/_/ / / / __ `/ _ \/ __ \
/ /_/ />  </ /_/ / /_/ /  __/ / / /
\____/_/|_|\__, /\__, /\___/_/ /_/ 
          /____//____/   

"""

function serverwelcome(host::String, port::Int, docs::Bool, metrics::Bool)
    printstyled(oxygen_title, color = :blue, bold = true)
    @info "📦 Version 1.4.8 (2024-02-01)"
    @info "✅ Started server: http://$host:$port" 
    docs    && @info "📖 Documentation: http://$host:$port$docspath"
    metrics && @info "📊 Metrics: http://$host:$port$docspath/metrics"
end



# TODO

# CRON STATE
# Depends on internalrequest and thus needs a full context to be passed in
"""
    starttasks()

Start all background repeat tasks
"""
function starttasks()
    timers[] = []
    tasks = getrepeatasks()

    # exit function early if no tasks are register
    if isempty(tasks)
        return 
    end

    println()
    printstyled("[ Starting $(length(tasks)) Repeat Task(s)\n", color = :magenta, bold = true)  
    
    for task in tasks
        path, httpmethod, interval = task
        message = "method: $httpmethod, path: $path, inverval: $interval seconds"
        printstyled("[ Task: ", color = :magenta, bold = true)  
        println(message)
        action = (timer) -> internalrequest(HTTP.Request(httpmethod, path))
        timer = Timer(action, 0, interval=interval)
        push!(timers[], timer)   
    end
end 


# TODO

# CRON STATE
"""
Register all cron jobs 
"""
function registercronjobs()
    for job in getcronjobs()
        path, httpmethod, expression = job
        @cron expression path function()
            internalrequest(HTTP.Request(httpmethod, path))
        end
    end
end 

# CRON STATE
"""
    stoptasks()

Stop all background repeat tasks
"""
function stoptasks()
    for timer in timers[]
        if isopen(timer)
            close(timer)
        end
    end
    timers[] = []
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
function serve(router::Router, history::CircularDeque{HTTPTransaction}, mountedfolders::Set{String}, taggedroutes::Dict{String, TaggedRoute}; 
    middleware::Vector=[], 
    handler=stream_handler, 
    host="127.0.0.1", 
    port=8080, 
    serialize=true, 
    async=false, 
    catch_errors=true, 
    docs=true,
    metrics=true, 
    kwargs...)

    # compose our middleware ahead of time (so it only has to be built up once)
    configured_middelware = setupmiddleware(router, history; middleware, serialize, catch_errors, metrics)

    # The cleanup of resources are put at the topmost level in `methods.jl`

    return startserver((; router, history, mountedfolders, taggedroutes), host, port, docs, metrics, kwargs, async, (kwargs) ->  
            HTTP.serve!(handler(configured_middelware), host, port; kwargs...))
end


# CHANGE: router, passed to setupmiddleware
"""
    serveparallel(; middleware::Vector=[], handler=stream_handler, host="127.0.0.1", port=8080, queuesize=1024, serialize=true, async=false, catch_errors=true, docs=true, metrics=true, kwargs...)

Starts the webserver in streaming mode with your own custom request handler and spawns n - 1 worker 
threads to process individual requests. A Channel is used to schedule individual requests in FIFO order. 
Requests in the channel are then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(router::Router, history::CircularDeque{HTTPTransaction}, _handler::Handler, mountedfolders::Set{String}, taggedroutes::Dict{String, TaggedRoute}; 
    middleware::Vector=[], 
    handler=stream_handler, 
    host="127.0.0.1", 
    port=8080, 
    queuesize=1024, 
    serialize=true, 
    async=false, 
    catch_errors=true,
    docs=true,
    metrics=true, 
    kwargs...)

    # compose our middleware ahead of time (so it only has to be built up once)
    configured_middelware = setupmiddleware(router, history; middleware, serialize, catch_errors, metrics)

    server = startserver((; router, history, mountedfolders, taggedroutes), host, port, docs, metrics, kwargs, async, (kwargs) -> 
        StreamUtil.start(_handler, handler(configured_middelware); host=host, port=port, queuesize=queuesize, kwargs...)
    )
    return server # this value is returned if startserver() is ran in async mode
end


# CHANGE: router. 
"""
Compose the user & internally defined middleware functions together. Practically, this allows
users to 'chain' middleware functions like `serve(handler1, handler2, handler3)` when starting their 
application and have them execute in the order they were passed (left to right) for each incoming request
"""
function setupmiddleware(router::Router, history::CircularDeque{HTTPTransaction}; middleware::Vector=[], metrics::Bool=true, serialize::Bool=true, catch_errors::Bool=true) :: Function

    # determine if we have any special router or route-specific middleware
    custom_middleware = hasmiddleware() ? [compose(router, middleware)] : reverse(middleware)

    # check if we should use our default serialization middleware function
    serializer = serialize ? [DefaultSerializer(catch_errors)] : []

    # check if we need to track metrics
    collect_metrics = metrics ? [MetricsMiddleware(history, metrics)] : []

    # combine all our middleware functions
    return reduce(|>, [
        router,
        serializer...,
        custom_middleware...,
        collect_metrics...
    ])    
end

# CHANGE: Server could be passed as a reference
# OUTSIDE: uses resetstate 
# 
"""
Internal helper function to launch the server in a consistent way
"""
function startserver((; router, history, mountedfolders, taggedroutes), host, port, docs, metrics, kwargs, async, start)

    serverwelcome(host, port, docs, metrics)
    setup(router, history, mountedfolders, taggedroutes; docs, metrics)
    server = start(preprocesskwargs(kwargs)) # How does this one work!
    starttasks()
    registercronjobs()
    startcronjobs()
    if !async     
        try 
            wait(server)
        catch 
            println() # this pushes the "[ Info: Server on 127.0.0.1:8080 closing" to the next line
        end
    end

    return server
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
This function called right before serving the server, which is useful for performing any additional setup
"""
function setup(router::Router, history::CircularDeque{HTTPTransaction}, mountedfolders::Set{String}, taggedroutes::Dict{String, TaggedRoute}; docs::Bool, metrics::Bool)
    
    docs ? enabledocs() : disabledocs()

    if docs
        setupswagger((;router, mountedfolders, taggedroutes))
    end

    if metrics
        setupmetrics(router, history, mountedfolders, taggedroutes)
    end
end


"""
    internalrequest(req::HTTP.Request; middleware::Vector=[], serialize::Bool=true, catch_errors::Bool=true)

Directly call one of our other endpoints registered with the router, using your own middleware
and bypassing any globally defined middleware
"""
function internalrequest(router::Router, history::CircularDeque{HTTPTransaction}, req::HTTP.Request; middleware::Vector=[], metrics::Bool=true, serialize::Bool=true, catch_errors=true) :: HTTP.Response
    req.context[:ip] = "INTERNAL" # label internal requests
    return req |> setupmiddleware(router, history, middleware=middleware, metrics=metrics, serialize=serialize, catch_errors=catch_errors)
end


"""
Create a default serializer function that handles HTTP requests and formats the responses.
"""
function DefaultSerializer(catch_errors::Bool)
    return function(handle)
        return function(req::HTTP.Request)
            return handlerequest(catch_errors) do 
                response = handle(req)
                format_response!(req, response)
                return req.response
            end
        end
    end
end

function MetricsMiddleware(history::CircularDeque{HTTPTransaction}, catch_errors::Bool) # The top level here will be good for injecting `history` 
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


"""
    register(httpmethod::String, route::String, func::Function)

Register a request handler function with a path to the ROUTER
"""
function register((; router, mountedfolders, taggedroutes), httpmethod::String, route::Union{String,Function}, func::Function)

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
    
    variableRegex = r"{[a-zA-Z0-9_]+}"
    hasBraces = r"({)|(})"
    
    # determine if we have parameters defined in our path
    hasPathParams = contains(route, variableRegex)
    
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
    
    # create a map of paramter name to type definition
    func_map = Dict(name => type for (name, type) in zip(func_param_names, func_param_types))

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

    # strip off any regex patterns attached to our path parameters
    registerschema((; mountedfolders, taggedroutes),
        route, httpmethod, zip(func_param_names, func_param_types), Base.return_types(func))

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

    @suppress begin
        HTTP.register!(router, httpmethod, route, handle)
    end
end

# CHANGE: setupswagger needs to use register manually. Needs to accept router as an argument

# add the swagger and swagger/schema routes 
function setupswagger(ctx)

    if isdocsenabled()

        register(ctx, "GET", "$docspath", req -> swaggerhtml())

        register(ctx, "GET", "$docspath/swagger", req -> swaggerhtml())
    
        register(ctx, "GET", "$docspath/redoc", req -> redochtml())

        register(ctx, "GET", getschemapath(), req -> getschema())
    
    end

end

# add the swagger and swagger/schema routes 
function setupmetrics(router::Router, history::CircularDeque{HTTPTransaction}, mountedfolders::Set{String}, taggedroutes::Dict{String, TaggedRoute})

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

    staticfiles((;router, mountedfolders, taggedroutes), "$DATA_PATH/dashboard", "$docspath/metrics"; loadfile=loadfile)
    

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


    register((;router, mountedfolders, taggedroutes), "GET", "$docspath/metrics/data/{window}/{latest}", metrics)
end



# CHANGE: Export 
"""
    staticfiles(folder::String, mountdir::String; headers::Vector{Pair{String,String}}=[], loadfile::Union{Function,Nothing}=nothing)

Mount all files inside the /static folder (or user defined mount point). 
The `headers` array will get applied to all mounted files
"""
function staticfiles(ctx,
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
        # calculate the entire response once on load
        resp = file(filepath; loadfile=loadfile, headers=headers)

        register(ctx, "GET", currentroute, req -> resp)

        #@get "$currentroute" function(req)
        #   return resp
        #end
    end
    mountfolder(folder, mountdir, addroute)
end


# CHANGE: Export
"""
    dynamicfiles(folder::String, mountdir::String; headers::Vector{Pair{String,String}}=[], loadfile::Union{Function,Nothing}=nothing)

Mount all files inside the /static folder (or user defined mount point), 
but files are re-read on each request. The `headers` array will get applied to all mounted files
"""
function dynamicfiles(ctx,
        folder::String, 
        mountdir::String="static"; 
        headers::Vector=[], 
        loadfile::Union{Function,Nothing}=nothing
    )
    # remove the leading slash 
    if first(mountdir) == '/'
        mountdir = mountdir[2:end]
    end
    registermountedfolder(mountdir)
    function addroute(currentroute, filepath)

        register(ctx, "GET", currentroute, req -> file(filepath; loadfile=loadfile, headers=headers))

        # @get "$currentroute" function(req)   
        #     # calculate the entire response on each request
        #     return file(filepath; loadfile=loadfile, headers=headers)
        # end
    end
    mountfolder(folder, mountdir, addroute)    
end


end
