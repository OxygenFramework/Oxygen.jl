module Oxygen
using HTTP
using JSON3
using Sockets
using FromFile

@from "util.jl"         using Util
@from "fileutil.jl"     using FileUtil
@from "bodyparsers.jl"  using BodyParsers
@from "serverutil.jl"   using ServerUtil

export @get, @post, @put, @patch, @delete, @register, @route, @staticfiles, @dynamicfiles,
        serve, serveparallel, terminate, internalrequest, redirect, queryparams, 
        binary, text, json, html, file

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
    @staticfiles(folder::String, mountdir::String)

Mount all files inside the /static folder (or user defined mount point)
"""
macro staticfiles(folder::String, mountdir::String="static")
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
            # only parse path parameters if they are not of type Any or String
            function parsetype(type, value)
                return type == Any || type == String ? value : parse(type, value)
            end
            function (req) 
                split_path = HTTP.URIs.splitpath(req.target)
                # extract path values in the order they should be passed to our function
                path_values = [split_path[index] for (_, _, index) in $param_positions] 
                # convert params to their designated type (if applicable)
                pathParams = [parsetype(type, value) for (type, value) in zip($func_param_types, path_values)]   
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
                handle(req)
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


end