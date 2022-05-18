module Main 
    import HTTP
    import JSON3
    import StructTypes

    include("../src/fastapi.jl")
    using .FastApi

    struct Animal
        id::Int
        type::String
        name::String
    end

    # Add a supporting struct type definition to the Animal struct
    StructTypes.StructType(::Type{Animal}) = StructTypes.Struct()

    @get "/" function (req) 
        return "home"
    end

    # Return the body of the request as a string
    @post "/echo-text" function (req::HTTP.Request)
        return text(req)
    end

    # demonstrates how to serialize JSON into a julia struct 
    @post "/animal" function (req)
        return json(req, Animal)
    end

    # Return the body of the request as a JSON object
    @post "/echo-json" function (req::HTTP.Request)
        return json(req)
    end

    # You can also return your own customized HTTP.Response object from an endpoint
    @get "/custom-response" function (req::HTTP.Request)
        test_value = 77.8
        return HTTP.Response(200, ["Content-Type" => "text/plain"], body = "$test_value")
    end

    # demonstate how to use path params (without type definitions)
    @get "/add/{a}/{b}" function (req::HTTP.Request, pathparams::Dict)
        return parse(Float64, pathparams["a"]) + parse(Float64, pathparams["b"])
    end

    # demonstate how to use path params with type definitions
    @get "/multi/{c:float}/{d:float}" function (req::HTTP.Request, pathparams)
        return pathparams["c"] * pathparams["d"]
    end

    # # Any object retuned from a function will automatically be converted into JSON (by default)
    @get "/json" function(req::HTTP.Request)
        return Dict("message" => "hello world", "animal" => Animal(1, "cat", "whiskers"))
    end

    @route ["GET", "POST"] "/demo" function(req)
        return Animal(1, "cat", "whiskers")
    end

    @get "/files" function (req)
        return file("demo/main.jl")
    end

    @staticfiles "demo"

    # start the web server
    serve()

end