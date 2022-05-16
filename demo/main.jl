include("../src/FastApi.jl")
import .FastApi
import HTTP
import JSON3
import StructTypes

struct Animal
    id::Int
    type::String
    name::String
end

Api = FastApi

StructTypes.StructType(::Type{Animal}) = StructTypes.Struct()

Api.@post "/query" function (req::HTTP.Request)
    return "dump"
end

Api.@get "/bah" function (req::HTTP.Request)
    return "wow"
end

Api.@get "/test" function (req::HTTP.Request)
    return 77.88
end

Api.@get "/add/{a}/{b}" function (req::HTTP.Request, params)
    return parse(Float64, params["a"]) + parse(Float64, params["b"])
end

Api.@get "/multi/{c:float}/{d:float}" function (req::HTTP.Request, pathparams::Dict)
    return pathparams["c"] * pathparams["d"]
end

Api.@get("/json",
    function(req::HTTP.Request)
        return Dict("message" => "hello world", "animal" => Animal(1, "cat", "whiskers"))
    end
)

Api.start()