# disable precompilation b/c this module defines several macros
__precompile__(false)

module ServerUtil

using HTTP 
using Sockets 
using JSON3

include("util.jl");         using .Util
include("fileutil.jl");     using .FileUtil
include("streamutil.jl");   using .StreamUtil
include("autodoc.jl");      using .AutoDoc

export @get, @post, @put, @patch, @delete, @route, @staticfiles, @dynamicfiles,
        start, serve, serveparallel, terminate, internalrequest,
        configdocs, mergeschema, setschema, getschema,
        enabledocs, disabledocs, isdocsenabled, registermountedfolder

global const ROUTER = Ref{HTTP.Handlers.Router}(HTTP.Router())
global const server = Ref{Union{Sockets.TCPServer, Nothing}}(nothing) 

oxygen_title = raw"""
   ____                            
  / __ \_  ____  ______ ____  ____ 
 / / / / |/_/ / / / __ `/ _ \/ __ \
/ /_/ />  </ /_/ / /_/ /  __/ / / /
\____/_/|_|\__, /\__, /\___/_/ /_/ 
          /____//____/   

"""

function serverwelcome(host::String, port::Int64)
    printstyled(oxygen_title, color = :blue, bold = true)  
    @info "Starting server: http://$host:$port" 
end

"""
    serve(; host="127.0.0.1", port=8080, kwargs...)

Start the webserver with the default request handler
"""
function serve(; host="127.0.0.1", port=8080, kwargs...)
    serverwelcome(host, port)
    setup()
    kwargs = preprocesskwargs(kwargs) 
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    HTTP.serve(req -> DefaultHandler(req), host, port; server=server[], kwargs...)
end


"""
    serve(handler::Function; host="127.0.0.1", port=8080, kwargs...)

Start the webserver with your own custom request handler
"""
function serve(handler::Function; host="127.0.0.1", port=8080, kwargs...)
    serverwelcome(host, port)
    setup()
    kwargs = preprocesskwargs(kwargs) 
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    HTTP.serve(req -> handler(req, getrouter(), DefaultHandler), host, port; server=server[], kwargs...)
end


"""
    serveparallel(; host="127.0.0.1", port=8080, queuesize=1024, kwargs...)

Starts the webserver in streaming mode and spawns n - 1 worker threads to process individual requests.
A Channel is used to schedule individual requests in FIFO order. Requests in the channel are
then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(; host="127.0.0.1", port=8080, queuesize=1024, kwargs...)
    serverwelcome(host, port)
    setup()
    kwargs = preprocesskwargs(kwargs) 
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    StreamUtil.start(server[], req -> DefaultHandler(req); queuesize=queuesize, kwargs...)
end


"""
    serveparallel(handler::Function; host="127.0.0.1", port=8080, queuesize=1024, kwargs...)

Starts the webserver in streaming mode with your own custom request handler and spawns n - 1 worker 
threads to process individual requests. A Channel is used to schedule individual requests in FIFO order. 
Requests in the channel are then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(handler::Function; host="127.0.0.1", port=8080, queuesize=1024, kwargs...)
    serverwelcome(host, port)
    setup()
    kwargs = preprocesskwargs(kwargs) 
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    StreamUtil.start(server[], req -> handler(req, getrouter(), DefaultHandler); queuesize=queuesize, kwargs...)
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
        close(server[])
    end
end


"""
    internalrequest(request::HTTP.Request)

Directly call one of our other endpoints registered with the router
"""
function internalrequest(req::HTTP.Request) :: HTTP.Response
    return DefaultHandler(req)
end


"""
    internalrequest(request::HTTP.Request, handler::Function)

Directly call one of our other endpoints registered with the router, using your own Handler function
"""
function internalrequest(req::HTTP.Request, handler::Function) :: HTTP.Response
    return handler(req, getrouter(), DefaultHandler)
end


"""
    getrouter()

returns the interal http router for this application
"""
function getrouter() :: HTTP.Handlers.Router
    return ROUTER[]
end 

function DefaultHandler(req::HTTP.Request) :: HTTP.Response
    try
        response_body = HTTP.handle(getrouter(), req)
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
        function addroute(path, headers, filepath, registeredpaths; code=200)
            # only serve the original unchanged file contents using this variable
            local body = file(filepath)
            eval(
                quote 
                    @get $path function(req)
                        # return 404 for paths that don't match our files
                        validpath::Bool = get($registeredpaths, req.target, false)
                        return validpath ? HTTP.Response($code, $headers , body=$body) : HTTP.Response(404)
                    end
                end
            )
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
        function addroute(path, headers, filepath, registeredpaths; code = 200)
            eval(
                quote 
                    @get $path function(req)   
                        # return 404 for paths that don't match our files
                        validpath::Bool = get($registeredpaths, req.target, false)
                        return validpath ?  HTTP.Response($code, $headers , body=file($filepath)) : HTTP.Response(404) 
                    end
                end
            )
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
        local func = $(esc(func))
        local path = $(esc(path))
        for method in eval($methods)
            eval(:(@register $method $path $func))
        end
    end  
end


"""
    @register(httpmethod::String, path::String, func::Function)

Register a request handler function with a path to the ROUTER
"""
macro register(httpmethod, path, func)
    
    local router = getrouter()
    local variableRegex = r"{[a-zA-Z0-9_]+}"
    local hasBraces = r"({)|(})"

    # determine if we have parameters defined in our path
    local hasPathParams = contains(path, variableRegex)
    local cleanpath = hasPathParams ? replace(path, variableRegex => "*") : path 
    
    # track which index the params are located in
    local positions = []
    for (index, value) in enumerate(HTTP.URIs.splitpath(path)) 
        if contains(value, hasBraces)
            push!(positions, (index, replace(value, hasBraces => "")))
        end
    end

    local method = first(methods(func))
    local numfields = method.nargs

    # extract the function handler's field names & types 
    local fields = [x for x in fieldtypes(method.sig)]
    local func_param_names = [String(param) for param in method_argnames(method)[3:end]]
    local func_param_types = splice!(Array(fields), 3:numfields)

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
            throw("Your request handler is missing a parameter: '$path_param' defined in this route: $path")
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
            throw("Your path is missing a parameter: '$func_param' which needs to be added to this route: $path")
        else 
            push!(param_positions, matched)
        end
    end

    registerchema(path, httpmethod, zip(func_param_names, func_param_types), Base.return_types(func))

    local action = esc(func)

     # case 1.) The request handler is an anonymous function (don't parse out path params)
    if numfields <= 1
        local handle = quote 
            function (req)
                $action()
            end
        end
    # case 2.) This route has path params, so we need to parse parameters and pass them to the request handler
    elseif hasPathParams && numfields > 2
        local handle = quote
            function (req) 
                split_path = HTTP.URIs.splitpath(req.target)
                # extract path values in the order they should be passed to our function
                path_values = [split_path[index] for (_, _, index) in $param_positions] 
                # convert params to their designated type (if applicable)
                pathParams = [parseparam(type, value) for (type, value) in zip($func_param_types, path_values)]   
                $action(req, pathParams...)
            end
        end
    # case 3.) This function should only get passed the request object
    else 
        local handle = quote 
            function (req) 
                $action(req)
            end
        end
    end

    local requesthandler = quote 
        local handle = $handle
        function (req)
            try 
                return handle(req)
            catch error
                @error "ERROR: " exception=(error, catch_backtrace())
                return HTTP.Response(500, "The Server encountered a problem")
            end
        end
    end

    quote 
        HTTP.@register($router, $httpmethod, $cleanpath, $requesthandler)
    end
end


# add the swagger and swagger/schema routes 
function setupswagger()

    if !isdocsenabled()
        return
    end
    
    @route ["GET"] "$docspath" function()
        return swaggerhtml()
    end

    @route ["GET"] "$schemapath" function()
        return getschema() 
    end
    
end


end