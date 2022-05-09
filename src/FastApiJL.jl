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

    macro register(method, path, func)
        quote 
            HTTP.@register(ROUTER, $method, $path, $(esc(func)))
        end
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

    function start(port=8081)
        HTTP.serve(JSONHandler, Sockets.localhost, port)
    end

    function start(customHandler::Function, port=8081)
        HTTP.serve(req -> customHandler(req), Sockets.localhost, port)
    end

end