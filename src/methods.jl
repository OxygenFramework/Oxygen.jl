# This is where methods are coupled to a global state

#using Infiltrator
#@infiltrate
# Check if I can get this running 

function resetstate()
    Core.resetstate((; ROUTER))
end


function serve(; 
      middleware::Vector=[], 
      handler=Core.stream_handler, 
      host="127.0.0.1", 
      port=8080, 
      serialize=true, 
      async=false, 
      catch_errors=true, 
      docs=true,
      metrics=true, 
      kwargs...) 
    return Core.serve(ROUTER[]; 
                 middleware, handler, port, serialize, 
                 async, catch_errors, docs, metrics, kwargs...)
end


function serveparallel(; 
                       middleware::Vector=[], 
                       handler=Core.stream_handler, 
                       host="127.0.0.1", 
                       port=8080, 
                       queuesize=1024, 
                       serialize=true, 
                       async=false, 
                       catch_errors=true,
                       docs=true,
                       metrics=true, 
                       kwargs...)

    return serveparallel(ROUTER[],                  
                         middleware, handler, port, queuesize, serialize, 
                         async, catch_errors, docs, metrics, kwargs...)
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
        Core.register(ROUTER[], method, path, func)
    end
end

# This variation supports the do..block syntax
route(func::Function, methods::Vector{String}, path::Union{String,Function}) = route(methods, path, func)


# REFACTOR: theese are internal methods which shouldn't be exported
# these utility functions help reduce the amount of repeated hardcoded values
#get_handler(path::Union{String,Function}, func::Function)     = route(["GET"], path, func)
#post_handler(path::Union{String,Function}, func::Function)    = route(["POST"], path, func)
#put_handler(path::Union{String,Function}, func::Function)     = route(["PUT"], path, func)
#patch_handler(path::Union{String,Function}, func::Function)   = route(["PATCH"], path, func)
#delete_handler(path::Union{String,Function}, func::Function)  = route(["DELETE"], path, func)



### Core Routing Functions Support for do..end Syntax ###

Base.get(func::Function, path::String)      = route(["GET"], path, func)
Base.get(func::Function, path::Function)    = route(["GET"], path, func)

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
) = Core.staticfiles(ROUTER[], folder, mountdir, headers, laodfile)


dynamicfiles(
    folder::String, 
    mountdir::String="static"; 
    headers::Vector=[], 
    loadfile::Union{Function,Nothing}=nothing
) = Core.dynamicfiles(ROUTER[], folder, mountdir, headers, laodfile)


internalrequest(req::HTTP.Request; middleware::Vector=[], metrics::Bool=true, serialize::Bool=true, catch_errors=true) = Core.internalrequest(ROUTER[], req; middleware, metrics, serialize, catch_errors)
