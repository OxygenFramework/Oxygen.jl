module FastApiJL
    import HTTP
    import Sockets
    import JSON3

    # define REST endpoints to dispatch to "service" functions
    const ROUTER = HTTP.Router()

    function start(port=8081)
        HTTP.serve(JSONHandler, Sockets.localhost, port)
    end

    function start(customHandler::Function, port=8081)
        HTTP.serve(req -> customHandler(req, ROUTER), Sockets.localhost, port)
    end

    macro get(path, func)
        quote 
            @register "GET" $path $(esc(func))
        end
    end

    macro post(path, func)
        quote 
            @register "POST" $path $(esc(func))
        end
    end

    macro put(path, func)
        quote 
            @register "PUT" $path $(esc(func))
        end
    end

    macro patch(path, func)
        quote 
            @register "PATCH" $path $(esc(func))
        end
    end

    macro delete(path, func)
        quote 
            @register "DELETE" $path $(esc(func))
        end
    end

    function JSONHandler(req::HTTP.Request)
        try
            # first check if there's any request body
            body = IOBuffer(HTTP.payload(req))
            if eof(body)
                # no request body
                response_body = HTTP.handle(ROUTER, req)
            else
                # there's a body, so pass it on to the handler we dispatch to
                response_body = HTTP.handle(ROUTER, req, JSON3.read(body))
            end
            return HTTP.Response(200, JSON3.write(response_body))
        catch error
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The Server encountered a problem")
        end

    end


    macro register(method, path, func)
        local variableRegex = r"{[a-zA-Z0-9_]+}"
        local bracesRegex = r"({)|(})"

        # determine if we have parameters defined in our path
        local hasParams = contains(path, bracesRegex)
        local cleanpath = hasParams ? replace(path, variableRegex => "*") : path 

        # track which index the params are located in
        local splitpath = HTTP.URIs.splitpath(path)
        local paramPositions = Dict(index => replace(value, bracesRegex => "") for (index, value) in enumerate(splitpath) if contains(value, bracesRegex)) 

        local handleRequest = quote 
            function (req)
                if $hasParams
                    local splitPath = enumerate(HTTP.URIs.splitpath(req.target))
                    local params = Dict($paramPositions[index] => value for (index, value) in splitPath if haskey($paramPositions, index))
                    local action = $(esc(func))
                    action(req, params)
                else
                    local action = $(esc(func))
                    action(req)
                end
            end
        end

        quote 
            HTTP.@register(ROUTER, $method, $cleanpath, $handleRequest)
        end
    end

end