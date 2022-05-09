include("../src/FastApiJL.jl")
import .FastApiJL
import HTTP
import JSON3
import StructTypes

struct Animal
    id::Int
    type::String
    name::String
end

StructTypes.StructType(::Type{Animal}) = StructTypes.Struct()

Api = FastApiJL


Api.@post "/datadump" function (req::HTTP.Request)
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

Api.@get "/multi/{a}/{b}" function (req::HTTP.Request, params)
    return parse(Float64, params["b"]) * parse(Float64, params["b"])
end

Api.@get("/json",
    function (req::HTTP.Request)
        return Dict("message" => "hello world", "animal" => JSON3.write(Animal(1, "feline", "whiskers")))
    end
)

Api.start()