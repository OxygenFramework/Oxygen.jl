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

F = FastApi

StructTypes.StructType(::Type{Animal}) = StructTypes.Struct()


F.@post "/animal" function (req)
    return F.json(req, Animal)
end

F.@post "/text-text" function (req::HTTP.Request)
    return F.text(req)
end

F.@post "/echo-json" function (req::HTTP.Request)
    return F.json(req)
end

F.@get "/custom-response" function (req::HTTP.Request)
    test_value = 77.8
    return HTTP.Response( 200, ["Content-Type" => "text/plain"], body = "$test_value")
end

F.@get "/add/{a}/{b}" function (req::HTTP.Request, params::Dict)
    return parse(Float64, params["a"]) + parse(Float64, params["b"])
end

F.@get "/multi/{c:float}/{d:float}" function (req::HTTP.Request)
    return 3
    # return pathparams["c"] * pathparams["d"]
end

F.@get("/json",
    function(req::HTTP.Request)
        return Dict("message" => "hello world", "animal" => Animal(1, "cat", "whiskers"))
    end
)

F.start()