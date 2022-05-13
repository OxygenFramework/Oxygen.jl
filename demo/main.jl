include("../src/FastApi.jl")
import .FastApi
import HTTP
import JSON3

struct Animal
    id::Int
    type::String
    name::String
end

Api = FastApi


Api.@addstruct(::Type{Animal})

Api.@post "/query" function (req::Api.Request)
    return "dump"
end

Api.@get "/bah" function (req::Api.Request)
    return "wow"
end

Api.@get "/test" function (req::Api.Request)
    return 77.88
end

Api.@get "/add/{a}/{b}" function (req::Api.Request)
    params = req.pathparams
    return parse(Float64, params["a"]) + parse(Float64, params["b"])
end

Api.@get "/multi/{c:float}/{d:float}" function (req::Api.Request)
    pathparams = req.pathparams
    return pathparams["c"] * pathparams["d"]
end

Api.@get("/json",
    function(req::Api.Request)
        return Dict("message" => "hello world", "animal" => Animal(1, "cat", "whiskers"))
    end
)

Api.start()