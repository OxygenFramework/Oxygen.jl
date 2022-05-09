module FastApiJL
    import HTTP
    import Sockets
    import JSON3

    # define REST endpoints to dispatch to "service" functions
    const ROUTER = HTTP.Router()

    function JSONHandler(req::HTTP.Request)
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
    end

    macro get(path, func)
        quote 
            @registerwithparams "GET" $path $(esc(func))
        end
    end

    macro post(path, func)
        quote 
            @registerwithparams "POST" $path $(esc(func))
        end
    end

    macro register(method, path, func)
        quote 
            HTTP.@register(ROUTER, $method, $path, $(esc(func)))
        end
    end

    macro registerwithparams(method, path, func)
        # determine if we have parameters defined in our path
        local hasParams = contains(path, ":")
        local cleanpath = hasParams ? replace(path, r":[a-z]+" => "*") : path 

        # track which index the params are located in
        local pattern = HTTP.URIs.splitpath(path)
        local paramPositions = Dict(index => value for (index, value) in enumerate(pattern) if contains(value, ":")) 
        
        quote 
            @register $method $cleanpath function (req)
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
    end


    function start(port=8081)
        HTTP.serve(JSONHandler, Sockets.localhost, port)
    end

    function start(customHandler::Function, port=8081)
        HTTP.serve(req -> customHandler(req), Sockets.localhost, port)
    end

end