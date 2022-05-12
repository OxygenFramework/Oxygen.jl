module FastApi
    import HTTP
    import JSON3
    import Sockets
    import StructTypes

    # define REST endpoints to dispatch to "service" functions
    const ROUTER = HTTP.Router()

    # Internal Struct Type Definitions
    StructTypes.StructType(::Type{HTTP.Messages.Response}) = StructTypes.Struct()

    function start(host=Sockets.localhost, port=8081; kwargs...)
        println("Starting server: $host:$port")
        HTTP.serve(JSONHandler, host, port, kwargs...)
    end

    function start(customHandler::Function, host=Sockets.localhost, port=8081; kwargs...)
        println("Starting server: $host:$port")
        HTTP.serve(req -> customHandler(req, ROUTER), Sockets.localhost, port, kwargs...)
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

    macro addstruct(customType::Expr)
        quote 
            StructTypes.StructType($(esc(customType))) = StructTypes.Struct()
        end
    end

    macro addorderedstruct(customType::Expr)
        quote 
            StructTypes.StructType($(esc(customType))) = StructTypes.OrderedStruct()
        end
    end

    macro addmutablestruct(customType::Expr)
        quote 
            StructTypes.StructType($(esc(customType))) = StructTypes.Mutable()
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

            # if a raw HTTP.Response object is returned, then don't do any extra processing on it
            if isa(response_body, HTTP.Messages.Response)
                return response_body 
            else 
                return HTTP.Response(200, JSON3.write(response_body))
            end 

        catch error
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The Server encountered a problem")
        end

    end

    function getvarname(key)
        return lowercase(split(key, ":")[1])
    end

    function getvartype(value)
        variableType = lowercase(split(value, ":")[2])
        typeconverters = [
            ("int", Int64),
            ("float", Float64),
            ("bool", Bool)
        ]
        for (name, type) in typeconverters
            if variableType == name
                return (x) -> parse(type, x)
            end
        end
        return (x) -> x
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
                positions[index] = getvarname(variable)
            end
            # track type definitions
            if contains(value, hasTypeDef)
                converters[index] = getvartype(variable)
            end
        end

        # helper functions to generate Key/Value pairs for our params dictionary
        local keygen = (index) -> getvarname(positions[index])
        local valuegen = (index, value) -> haskey(converters, index) ? converters[index](value) : value
      
        local handlerequest = quote 
            function (req)
                local uri = HTTP.URI(req.target)
                local queryparams = HTTP.queryparams(uri.query)
                local hasQueryParmas = !isempty(queryparams)
                if $hasPathParams
                    local splitPath = enumerate(HTTP.URIs.splitpath(req.target))
                    local pathParams = Dict($keygen(index) => $valuegen(index, value) for (index, value) in splitPath if haskey($positions, index))
                    local action = $(esc(func))
                    action(req, merge(queryparams, pathParams))
                else
                    local action = $(esc(func))
                    if hasQueryParmas
                        action(req, queryparams)
                    else 
                        action(req)
                    end
                end
            end
        end

        quote 
            HTTP.@register(ROUTER, $method, $cleanpath, $handlerequest)
        end
    end

end