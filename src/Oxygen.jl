module Oxygen
using HTTP
using JSON3
using Sockets

include("util.jl");         using .Util
include("fileutil.jl");     using .FileUtil
include("streamutil.jl");   using .StreamUtil
include("bodyparsers.jl");  using .BodyParsers
include("serverutil.jl");   using .ServerUtil

export @get, @post, @put, @patch, @delete, @register, @route, @staticfiles, @dynamicfiles,
        serve, serveparallel, terminate, internalrequest, queryparams, binary, text, json, 
        html, file


### Request helper functions ###

"""
    internalrequest(request::HTTP.Request)

Directly call one of our other endpoints registered with the router
"""
function internalrequest(req::HTTP.Request) :: HTTP.Response
    return DefaultHandler(req)
end

"""
    queryparams(request::HTTP.Request)

Parse's the query parameters from the Requests URL and return them as a Dict
"""
function queryparams(req::HTTP.Request) :: Dict
    local uri = HTTP.URI(req.target)
    return HTTP.queryparams(uri.query)
end

"""
    html(content::String; status::Int, headers::Pair)

A convenience funtion to return a String that should be interpreted as HTML
"""
function html(content::String; status = 200, headers = ["Content-Type" => "text/html; charset=utf-8"]) :: HTTP.Response
    return HTTP.Response(status, headers, body = content)
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
        function addroute(path, headers, filepath)
            # only serve the original unchanged file contents using this variable
            local body = file(filepath)
            eval(
                quote 
                    @get $path function (req)
                        return HTTP.Response(200, $headers , body=$body) 
                    end
                end
            )
        end
        @hostfiles($folder, $mountdir, addroute)
    end
    
end


"""
    @dynamicfiles(folder::String, mountdir::String)

Mount all files inside the /static folder (or user defined mount point), 
but files are re-read on each request
"""
macro dynamicfiles(folder::String, mountdir::String="static")
    quote 
        function addroute(path, headers, filepath)
            eval(
                quote 
                    @get $path function (req)   
                        return HTTP.Response(200, $headers , body=file($filepath)) 
                    end
                end
            )
        end
        @hostfiles($folder, $mountdir, addroute)
    end        
end


"""
    @register(httpmethod::String, path::String, func::Function)

Register a request handler function with a path to the ROUTER
"""
macro register(httpmethod, path, func)

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

    # ensure the path parms are present inside the function params 
    for (func_index, func_param) in enumerate(func_param_names)
        matched = nothing
        for (path_index, path_param) in positions
            if func_param == path_param 
                matched = (func_param, func_index, path_index)
                break
            end
        end
        if matched === nothing
            throw("Your path is missing a parameter: '$func_param' in this route: $path")
        else 
            push!(param_positions, matched)
        end
    end

    local handlerequest = quote 
        local action = $(esc(func))
        function (req)
            try 
                # don't pass any args if the function takes none
                if $numfields == 1 
                    action()
                # if endpoint has path parameters, make sure the attached function accepts them
                elseif $hasPathParams
                    split_path = HTTP.URIs.splitpath(req.target)
                    # extract path values in the order they should be passed to our function
                    path_values = [split_path[index] for (_, _, index) in $param_positions] 
                    # convert params to their designated type (if applicable)
                    pathParams = [type == Any ? value : parse(type, value) for (type, value) in zip($func_param_types, path_values)]   
                    action(req, pathParams...)
                else 
                    action(req)
                end
            catch error
                @error "ERROR: " exception=(error, catch_backtrace())
                return HTTP.Response(500, "The Server encountered a problem")
            end
        end
    end

    quote 
        HTTP.@register(ROUTER, $httpmethod, $cleanpath, $handlerequest)
    end
end

end