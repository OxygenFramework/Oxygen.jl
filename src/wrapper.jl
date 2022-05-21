module Wrapper
    using HTTP
    using JSON3
    using Sockets
    
    include("fileutil.jl")
    using .FileUtil

    export @get, @post, @put, @patch, @delete, @register, @route, @staticfiles, @dynamicfiles, serve, stop, internalrequest, queryparams, binary, text, json, html

    # define REST endpoints to dispatch to "service" functions
    const ROUTER = HTTP.Router()
    global server = nothing 

    "Directly call one of our other endpoints registerd with the router"
    function internalrequest(req::HTTP.Request, suppressErrors::Bool=false)
        return DefaultHandler(req, suppressErrors)
    end

    "start the webserver with the default request handler"
    function serve(host="127.0.0.1", port=8081, suppressErrors::Bool=false; kwargs...)
        println("Starting server: http://$host:$port")
        global server = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
        HTTP.serve(req -> DefaultHandler(req, suppressErrors), host, port; server=server, kwargs...)
    end

    "start the webserver with your own custom request handler"
    function serve(handler::Function, host="127.0.0.1", port=8081; kwargs...)
        println("Starting server: http://$host:$port")
        global server = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
        HTTP.serve(req -> handler(req, ROUTER, DefaultHandler), host, port; server=server, kwargs...)
    end

    "stops the webserver immediately"
    function stop()
        close(server)
    end

    function DefaultHandler(req::HTTP.Request, suppressErrors::Bool=false)
        try
            response_body = HTTP.handle(ROUTER, req, suppressErrors)
            # if a raw HTTP.Response object is returned, then don't do any extra processing on it
            if isa(response_body, HTTP.Messages.Response)
                return response_body 
            elseif isa(response_body, String)
                headers = ["Content-Type" => HTTP.sniff(response_body)]
                return HTTP.Response(200, headers , body=response_body)
            else 
                body = JSON3.write(response_body)
                headers = ["Content-Type" => "application/json; charset=utf-8"]
                return HTTP.Response(200, headers , body=body)
            end 
        catch error
            if !suppressErrors
                @error "ERROR: " exception=(error, catch_backtrace())
            end
            return HTTP.Response(500, "The Server encountered a problem")
        end
    end

    ### Request helper functions ###

    function queryparams(req::HTTP.Request)
        local uri = HTTP.URI(req.target)
        return HTTP.queryparams(uri.query)
    end

    function html(content::String; status = 200, headers = ["Content-Type" => "text/html; charset=utf-8"])
        return HTTP.Response(status, headers, body = content)
    end

    ### Helper functions used to parse the body of each Request

    function text(req::HTTP.Request)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : read(seekstart(body), String)
    end

    function binary(req::HTTP.Request)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : readavailable(body)
    end

    function json(req::HTTP.Request)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : JSON3.read(body)
    end

    function json(req::HTTP.Request, classtype)
        body = IOBuffer(HTTP.payload(req))
        return eof(body) ? nothing : JSON3.read(body, classtype)    
    end


    ### Helper functions used to parse the body of each Response

    function text(response::HTTP.Response)
        return String(response.body)
    end

    function json(response::HTTP.Response)
        return JSON3.read(String(response.body))
    end

    function json(response::HTTP.Response, classtype)
        return JSON3.read(String(response.body), classtype)
    end

    ### Core Macros ###

    macro get(path, func)
        quote 
            @route $path ["GET"] $(esc(func))
        end
    end

    macro post(path, func)
        quote 
            @route $path ["POST"] $(esc(func))
        end
    end

    macro put(path, func)
        quote 
            @route $path ["PUT"] $(esc(func))
        end
    end

    macro patch(path, func)
        quote 
            @route $path ["PATCH"] $(esc(func))
        end
    end

    macro delete(path, func)
        quote 
            @route $path ["DELETE"] $(esc(func))
        end
    end
    
    macro route(path, methods, func)
        quote 
            local func = $(esc(func))
            local path = $path
            for method in eval($methods)
                eval(:(@register $method $path $func))
            end
        end  
    end

    # walk through all files in a directory and apply a function to each file
    macro iteratefiles(folder::String, func)
        local target_files::Array{String} = getfiles(folder)
        quote 
            local action = $(esc(func))
            for filepath in $target_files
                 action(filepath)
            end  
         end
     end

    # mount all files inside the /static folder (or user defined mount point)
    macro staticfiles(folder::String, mountdir::String="static")
        quote 
            local directory = $mountdir
            @iteratefiles $folder function(filepath::String)

                # generate the path to mount the file to
                local mountpath = "/$directory/$filepath"

                # load file into memory on sever startup
                local body = file(filepath)

                # precalculate content type 
                local content_type = HTTP.sniff(body)
                local headers = ["Content-Type" => content_type]

                eval(
                    quote 
                        @get $mountpath function (req)
                            return HTTP.Response(200, $headers , body=$body) 
                        end
                    end
                )
            end
        end
        
    end

    # Mount all files inside the /static folder (or user defined mount point), 
    # but files are re-read on each request
    macro dynamicfiles(folder::String, mountdir::String="static")
        quote 
            local directory = $mountdir
            @iteratefiles $folder function(filepath::String)

                # generate the path to mount the file 
                local mountpath = "/$directory/$filepath"

                # precalculate content type 
                local content_type = HTTP.sniff(file(filepath))
                local headers = ["Content-Type" => content_type]

                eval(
                    quote 
                        @get $mountpath function (req)   
                            return HTTP.Response(200, $headers , body=file($filepath)) 
                        end
                    end
                )
            end
        end        
    end
    
    # Register a request handler function with a path to the ROUTER
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
                push!(positions, index)
            end
        end
        
        local hasPositions = !isempty(positions)
        local lower_bound = hasPositions ? first(positions) : 0
        local upper_bound = hasPositions ? last(positions) : 0

        # get the functions high-level signature
        local method = first(methods(func))
        # extract the fieldtypes 
        local fields = [x for x in fieldtypes(method.sig)]
        local numfields = fieldcount(method.sig)

        # extract the type of each argument 
        local pathtypes = splice!(Array(fields), 3:numfields)

        local handlerequest = quote 
            local action = $(esc(func))
            function (req, suppressErrors)
                try 
                    # don't pass any args if the function takes none
                    if $numfields == 1 
                        action()
                    # if endpoint has path parameters, make sure the attached function accepts them
                    elseif $hasPathParams & $hasPositions
                        path_values = splice!(HTTP.URIs.splitpath(req.target), $lower_bound:$upper_bound)
                        pathParams = [type == Any ? value : parse(type, value) for (type, value) in zip($pathtypes, path_values)]   
                        action(req, pathParams...)
                    else 
                        action(req)
                    end
                catch error
                    if !suppressErrors
                        @error "ERROR: " exception=(error, catch_backtrace())
                    end
                    return HTTP.Response(500, "The Server encountered a problem")
                end
            end
        end

        quote 
            HTTP.@register(ROUTER, $httpmethod, $cleanpath, $handlerequest)
        end
    end

end