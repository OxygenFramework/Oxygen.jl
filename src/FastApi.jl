module FastApi
    import HTTP
    import JSON3
    import Sockets
    import StructTypes

    include("util.jl")
    import .Util

    # define REST endpoints to dispatch to "service" functions
    const ROUTER = HTTP.Router()

    # Internal Struct Type Definitions
    StructTypes.StructType(::Type{HTTP.Messages.Response}) = StructTypes.Struct()

    struct Request 
        request :: HTTP.Request
        body :: Union{JSON3.Object, String, Nothing}
        pathparams :: Dict
        queryparams :: Dict
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
            local num_args = Util.countargs($(esc(func)))
            local action = $(esc(func))

            function (req)
                local pathParams = Dict()
                if $hasPathParams
                    local splitPath = enumerate(HTTP.URIs.splitpath(req.target))
                    pathParams = Dict($keygen(index) => $valuegen(index, value) for (index, value) in splitPath if haskey($positions, index))
                end
                inputs = [req, pathParams]
                args = splice!(inputs, 1:num_args)
                action(args...)
            end
        end

        quote 
            HTTP.@register(ROUTER, $method, $cleanpath, $handlerequest)
        end
    end

    function start(host=Sockets.localhost, port=8081; kwargs...)
        println("Starting server: $host:$port")
        HTTP.serve(defaultHandler, host, port, kwargs...)
    end

    function start(customHandler::Function, host=Sockets.localhost, port=8081; kwargs...)
        println("Starting server: $host:$port")
        HTTP.serve(req -> customHandler(req, ROUTER), Sockets.localhost, port, kwargs...)
    end

    function queryparams(req::HTTP.Request)
        local uri = HTTP.URI(req.target)
        return HTTP.queryparams(uri.query)
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

    function defaultHandler(req::HTTP.Request)
        try
            response_body = HTTP.handle(ROUTER, req)
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

end