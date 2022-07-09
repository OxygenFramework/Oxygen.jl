module Oxygen
using HTTP
using JSON3
using Sockets

include("util.jl" );        using .Util
include("fileutil.jl");     using .FileUtil
include("bodyparsers.jl");  using .BodyParsers
include("serverutil.jl");   using .ServerUtil

export @get, @post, @put, @patch, @delete, @route, @staticfiles, @dynamicfiles,
        serve, serveparallel, terminate, internalrequest, 
        redirect, queryparams, binary, text, json, html, file, 
        configdocs, mergeschema, setschema, getschema,
        enabledocs, disabledocs, isdocsenabled, router

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


end