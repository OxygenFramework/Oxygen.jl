module Wrapper
    import HTTP
    import JSON3
    import Sockets

    include("util.jl")
    using .Util

    include("fileutil.jl")
    using .FileUtil

    export @get, @post, @put, @patch, @delete, @register, @route, @mount, @staticfiles, serve, queryparams, binary, text, json, html

    # define REST endpoints to dispatch to "service" functions
    const ROUTER = HTTP.Router()

    function serve(host=Sockets.localhost, port=8081; kwargs...)
        println("Starting server: http://$host:$port")
        HTTP.serve(DefaultHandler, host, port, kwargs...)
    end

    function serve(handler::Function, host=Sockets.localhost, port=8081; kwargs...)
        println("Starting server: http://$host:$port")
        HTTP.serve(req -> handler(req, ROUTER, DefaultHandler), host, port, kwargs...)
    end

    function serve(sucessHandler::Function, errorHandler::Function, host=Sockets.localhost, port=8081; kwargs...)
        println("Starting server: http://$host:$port")
        function handle(req)
            try
                response_body = HTTP.handle(ROUTER, req)
                return sucessHandler(response_body) 
            catch error
                @error "ERROR: " exception=(error, catch_backtrace())
                return errorHandler(error)
            end
        end
        HTTP.serve(req -> handle(req), Sockets.localhost, port, kwargs...)
    end

    function DefaultHandler(req::HTTP.Request)
        try
            response_body = HTTP.handle(ROUTER, req)
            # if a raw HTTP.Response object is returned, then don't do any extra processing on it
            if isa(response_body, HTTP.Messages.Response)
                return response_body 
            elseif isa(response_body, String)
                headers = ["Content-Type" => "text/plain; charset=utf-8"]
                return HTTP.Response(200, headers , body=response_body)
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
    
    function queryparams(req::HTTP.Request)
        local uri = HTTP.URI(req.target)
        return HTTP.queryparams(uri.query)
    end

    function binary(req::HTTP.Request)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : readavailable(body)
    end

    function html(content::String; status = 200, headers = ["Content-Type" => "text/html; charset=utf-8"])
        return HTTP.Response(status, headers, body = content)
    end

    function text(req::HTTP.Request)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : read(seekstart(body), String)
    end

    function json(req::HTTP.Request)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : JSON3.read(body)
    end

    function json(req::HTTP.Request, classtype)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : JSON3.read(body, classtype)    
    end

    macro get(path, func)
        quote 
            @route ["GET"] $path $(esc(func))
        end
    end

    macro post(path, func)
        quote 
            @route ["POST"] $path $(esc(func))
        end
    end

    macro put(path, func)
        quote 
            @route ["PUT"] $path $(esc(func))
        end
    end

    macro patch(path, func)
        quote 
            @route ["PATCH"] $path $(esc(func))
        end
    end

    macro delete(path, func)
        quote 
            @route ["DELETE"] $path $(esc(func))
        end
    end
    
    macro route(methods, path, func)
        quote 
            local func = $(esc(func))
            local path = $path
            for method in eval($methods)
                eval(:(@register $method $path $func))
            end
        end  
    end

    macro staticfiles(folder::String, mount::String="static")
    
        # collect all files inside the given 
        target_files::Array{String} = []
        for (root, _, files) in walkdir(folder)
            for file in files
                push!(target_files, joinpath(root, file))
            end
        end
        
        # mount all files inside the /static folder (or user defined mount point)
        quote 
            local directory = $mount
            for filepath in $target_files
                mountpath = "/$directory/$filepath"
                eval(
                    quote 
                        @get $mountpath function (req)
                            content_type = FileUtil.getfilecontenttype($filepath)
                            headers = ["Content-Type" => "$content_type; charset=utf-8"]
                            body = FileUtil.file($filepath)
                            return HTTP.Response(200, headers , body=body) 
                        end
                    end
                )
            end
        end
        
    end
     
    macro register(method, path, func)

        local variableRegex = r"{[a-zA-Z0-9_]+:*[a-z]*}"
        local hasTypeDef = r":[a-z]+"
        local hasBraces = r"({)|(})"

        # determine if we have parameters defined in our path
        local hasPathParams = contains(path, variableRegex)
        local cleanpath = hasPathParams ? replace(path, variableRegex => "*") : path 

        # track which index the params are located in
        local splitpath = HTTP.URIs.splitpath(path)
        local positions = Dict()
        local converters = Dict()

        for (index, value) in enumerate(splitpath) 
            variable = replace(value, hasBraces => "")                
            # track variable names & positions
            if contains(value, hasBraces)
                positions[index] = Util.getvarname(variable)
            end
            # track type definitions
            if contains(value, hasTypeDef)
                converters[index] = Util.getvartype(variable)
            end
        end

        # helper functions to generate Key/Value pairs for our params dictionary
        local keygen = (index) -> Util.getvarname(positions[index])
        local valuegen = (index, value) -> haskey(converters, index) ? converters[index](value) : value

        local handlerequest = quote 
            local action = $(esc(func))
            function (req)
                # if endpoint has path parameters, make sure the attached function accepts them
                if $hasPathParams
                    splitPath = enumerate(HTTP.URIs.splitpath(req.target))
                    pathParams = Dict($keygen(index) => $valuegen(index, value) for (index, value) in splitPath if haskey($positions, index))
                    action(req, pathParams)
                else 
                    action(req)
                end
            end
        end

        quote 
            HTTP.@register(ROUTER, $method, $cleanpath, $handlerequest)
        end
    end

end