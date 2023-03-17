module Core

using HTTP 
using Sockets 
using JSON3

include("util.jl");         using .Util
include("fileutil.jl");     using .FileUtil
include("streamutil.jl");   using .StreamUtil
include("autodoc.jl");      using .AutoDoc

export @get, @post, @put, @patch, @delete, @route, @staticfiles, @dynamicfiles, @cron,
        start, serve, serveparallel, terminate, internalrequest, file,
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, registermountedfolder,
        starttasks, stoptasks, resetstate, startcronjobs, stopcronjobs

global const ROUTER = Ref{HTTP.Handlers.Router}(HTTP.Router())
global const server = Ref{Union{HTTP.Server, Nothing}}(nothing) 
global const timers = Ref{Vector{Timer}}([])

oxygen_title = raw"""
   ____                            
  / __ \_  ____  ______ ____  ____ 
 / / / / |/_/ / / / __ `/ _ \/ __ \
/ /_/ />  </ /_/ / /_/ /  __/ / / /
\____/_/|_|\__, /\__, /\___/_/ /_/ 
          /____//____/   

"""

function serverwelcome(host::String, port::Int)
    printstyled(oxygen_title, color = :blue, bold = true)  
    @info "✅ Started server: http://$host:$port" 
    @info "📖 Documentation: http://$host:$port$docspath"
end


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
    serve(; middleware::Vector=[], host="127.0.0.1", port=8080, serialize=true, async=false, kwargs...)

Start the webserver with your own custom request handler
"""
function serve(; middleware::Vector=[], host="127.0.0.1", port=8080, serialize=true, async=false, kwargs...)
    startserver(host, port, kwargs, async, (kwargs) -> 
        HTTP.serve!(setupmiddleware(middleware=middleware, serialize=serialize), host, port; kwargs...)
    )
end

"""
    serveparallel(; middleware::Vector=[], host="127.0.0.1", port=8080, queuesize=1024, serialize=true, async=false, kwargs...)

Starts the webserver in streaming mode with your own custom request handler and spawns n - 1 worker 
threads to process individual requests. A Channel is used to schedule individual requests in FIFO order. 
Requests in the channel are then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(; middleware::Vector=[], host="127.0.0.1", port=8080, queuesize=1024, serialize=true, async=false, kwargs...)
    startserver(host, port, kwargs, async, (kwargs) -> 
        StreamUtil.start(setupmiddleware(middleware=middleware, serialize=serialize); host=host, port=port, queuesize=queuesize, kwargs...)
    )
end



"""
Compose the user & internally defined middleware functions together. Practically, this allows
users to 'chain' middleware functions like `serve(handler1, handler2, handler3)` when starting their 
application and have them execute in the order they were passed (left to right) for each incoming request
"""
function setupmiddleware(;middleware::Vector = [], serialize::Bool=true) :: Function
    # determine if we have any special router or route-specific middleware
    custom_middleware = hasmiddleware() ? [compose(getrouter(), middleware)] : reverse(middleware)
    # check if we should use our default serialization middleware function
    serialized = serialize ? [DefaultSerializer] : [DefaultHandler]
    # combine all our middleware functions
    return reduce(|>, [getrouter(), serialized..., custom_middleware...])    
end

"""
Internal helper function to launch the server in a consistent way
"""
function startserver(host, port, kwargs, async, start)
    try
        serverwelcome(host, port)
        setup()
        server[] = start(preprocesskwargs(kwargs))
        starttasks()
        registercronjobs()
        startcronjobs()
        if !async     
            wait(server[])
        end
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

"""
Reset all the internal state variables
"""
function resetstate()
    # reset this modules state variables 
    timers[] = []         
    ROUTER[] = HTTP.Router()
    server[] = nothing
    # reset autodocs state variables
    resetstatevariables()
    # reset cron module state
    resetcronstate()
end


"""
Used to overwrite defaults to any incoming keyword arguments
"""
function preprocesskwargs(kwargs)
    kwargs_dict = Dict{Symbol, Any}(kwargs)
    # user passed no loggin preferences - use defualt logging format 
    if isempty(kwargs_dict) || !haskey(kwargs_dict, :access_log)
        kwargs_dict[:access_log] = logfmt"$time_iso8601 - $remote_addr:$remote_port - \"$request\" $status"
    end  
    return kwargs_dict
end



"""
This function called right before serving the server, which is useful for performing any additional setup
"""
function setup()
    setupswagger()
end


"""
    terminate()

stops the webserver immediately
"""
function terminate()
    if !isnothing(server[]) && isopen(server[])
        # stop background cron jobs
        stopcronjobs()
        # stop background tasks
        stoptasks()
        # stop any background worker threads
        StreamUtil.stop()
        # stop server
        close(server[])
    end
end


"""
    internalrequest(req::HTTP.Request; middleware::Vector=[], serialize::Bool=true)

Directly call one of our other endpoints registered with the router, using your own middleware
and bypassing any globally defined middleware
"""
function internalrequest(req::HTTP.Request; middleware::Vector=[], serialize::Bool=true) :: HTTP.Response
    return req |> setupmiddleware(middleware=middleware, serialize=serialize) 
end


"""
    getrouter()

returns the interal http router for this application
"""
function getrouter() 
    return ROUTER[]
end 

"""
Provide an empty handler function, so that our middleware chain isn't broken
"""
function DefaultHandler(handle)
    return function(req::HTTP.Request)
        try 
            return handle(req)         
        catch error
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The Server encountered a problem")
        end  
    end
end

function DefaultSerializer(handle)
    return function(req::HTTP.Request)
        try
            response_body = handle(req)            
            # case 1.) if a raw HTTP.Response object is returned, then don't do any extra processing on it
            if isa(response_body, HTTP.Messages.Response)
                return response_body 
            # case 2.) a string is returned, so try to lookup the content type to see if it's a special data type
            elseif isa(response_body, String)
                headers = ["Content-Type" => HTTP.sniff(response_body)]
                return HTTP.Response(200, headers , body=response_body)
            # case 3.) An object of some type was returned and should be serialized into JSON 
            else 
                body = JSON3.write(response_body)
                headers = ["Content-Type" => "application/json; charset=utf-8"]
                return HTTP.Response(200, headers , body=body)
            end 
        catch error
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The Server encountered a problem")
        end   
    end
end

### Core Macros ###

"""
    @get(path::String, func::Function)

Used to register a function to a specific endpoint to handle GET requests  
"""
macro get(path, func)
    quote 
        @route ["GET"] $(esc(path)) $(esc(func))
    end
end

"""
    @post(path::String, func::Function)

Used to register a function to a specific endpoint to handle POST requests
"""
macro post(path, func)
    quote 
        @route ["POST"] $(esc(path)) $(esc(func))
    end
end

"""
    @put(path::String, func::Function)

Used to register a function to a specific endpoint to handle PUT requests
"""
macro put(path, func)
    quote 
        @route ["PUT"] $(esc(path)) $(esc(func))
    end
end

"""
    @patch(path::String, func::Function)

Used to register a function to a specific endpoint to handle PATCH requests
"""
macro patch(path, func)
    quote 
        @route ["PATCH"] $(esc(path)) $(esc(func))
    end
end


"""
    @delete(path::String, func::Function)

Used to register a function to a specific endpoint to handle DELETE requests
"""
macro delete(path, func)
    quote 
        @route ["DELETE"] $(esc(path)) $(esc(func))
    end
end

"""
    @staticfiles(folder::String, mountdir::String)

Mount all files inside the /static folder (or user defined mount point)
"""
macro staticfiles(folder::String, mountdir::String="static")
    registermountedfolder(mountdir)
    quote 
        function addroute(currentroute, headers, filepath, registeredpaths; code=200)
            local body = file(filepath)
            @get currentroute function(req)
                # return 404 for paths that don't match our files
                validpath::Bool = get(registeredpaths, req.target, false)
                return validpath ? HTTP.Response(code, headers , body=body) : HTTP.Response(404)
            end
        end
        @mountfolder($folder, $mountdir, addroute)
    end
end


"""
    @dynamicfiles(folder::String, mountdir::String)

Mount all files inside the /static folder (or user defined mount point), 
but files are re-read on each request
"""
macro dynamicfiles(folder::String, mountdir::String="static")
    registermountedfolder(mountdir)
    quote 
        function addroute(currentroute, headers, filepath, registeredpaths; code = 200)
            @get currentroute function(req)   
                # return 404 for paths that don't match our files
                validpath::Bool = get(registeredpaths, req.target, false)
                return validpath ?  HTTP.Response(code, headers , body=file(filepath)) : HTTP.Response(404) 
            end
        end
        @mountfolder($folder, $mountdir, addroute)
    end        
end

"""
    @route(methods::Array{String}, path::String, func::Function)

Used to register a function to a specific endpoint to handle mulitiple request types
"""
macro route(methods, path, func)
    quote 
        for method in $methods
            @register(method, $(esc(path)), $(esc(func)))
        end
    end  
end


"""
    @register(httpmethod::String, path::String, func::Function)

Register a request handler function with a path to the ROUTER
"""
macro register(httpmethod, path, func)
    return quote 
  
        local method_type = $(esc(httpmethod))
        local route = $(esc(path))
        local action = $(esc(func))
  
        # check if path is a callable function (that means it's a router higher-order-function)
        if !isempty(methods(route))

            # This is true when the user passes the router() directly to the path.
            # We call the generated function without args so it uses the default args 
            # from the parent function.
            if countargs(route) == 1
                route = route()
            end

            # If it's still a function, then that means this is from the 3rd inner function 
            # defined in the createrouter() function.
            if countargs(route) == 2
                route = route(method_type)
            end
            
        end

        local router = getrouter()
        local variableRegex = r"{[a-zA-Z0-9_]+}"
        local hasBraces = r"({)|(})"

        # determine if we have parameters defined in our path
        local hasPathParams = contains(route, variableRegex)
        
        # track which index the params are located in
        local positions = []
        for (index, value) in enumerate(HTTP.URIs.splitpath(route)) 
            if contains(value, hasBraces)
                # extract the variable name
                variable = replace(value, hasBraces => "") |> x -> split(x, ":") |> first        
                push!(positions, (index, variable))
            end
        end

        local method = first(methods(action))
        local numfields = method.nargs

        # extract the function handler's field names & types 
        local fields = [x for x in fieldtypes(method.sig)]
        local func_param_names = [String(param) for param in Base.method_argnames(method)[3:end]]
        local func_param_types = splice!(Array(fields), 3:numfields)
        
        # create a map of paramter name to type definition
        local func_map = Dict(name => type for (name, type) in zip(func_param_names, func_param_types))

        # each tuple tracks where the param is refereced (variable, function index, path index)
        local param_positions::Array{Tuple{String, Int, Int}} = []

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
        registerschema(route, method_type, zip(func_param_names, func_param_types), Base.return_types(action))

        # case 1.) The request handler is an anonymous function (don't parse out path params)
        if numfields <= 1
            local handle = function (req)
                action()
            end   
        # case 2.) This route has path params, so we need to parse parameters and pass them to the request handler
        elseif hasPathParams && numfields > 2
            local handle = function (req) 
                # get all path parameters
                params = HTTP.getparams(req)
                # convert params to their designated type (if applicable)
                pathParams = [parseparam(func_map[name], params[name]) for name in func_param_names]   
                # pass all parameters to handler in the correct order 
                action(req, pathParams...)
            end
        # case 3.) This function should only get passed the request object
        else 
            local handle = function (req) 
                action(req)
            end
        end

        local requesthandler = function (req)
            try 
                return handle(req)
            catch error
                @error "ERROR: " exception=(error, catch_backtrace())
                return HTTP.Response(500, "The Server encountered a problem")
            end
        end

        HTTP.register!(router, method_type, route, requesthandler)
    end 
end


# add the swagger and swagger/schema routes 
function setupswagger()

    if !isdocsenabled()
        return
    end

    @get docspath function()
        return swaggerhtml()
    end

    @get schemapath function()
        return getschema() 
    end
    
end


end