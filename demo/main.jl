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

Api.@get "/query" function (req::HTTP.Request, a)
    println(a)
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

Api.@get "/multi/{c:float}/{d:float}" function (req::HTTP.Request, params)
    println(params)
    return params["c"] * params["d"]
end

Api.@get("/json",
    function (req::HTTP.Request)
        return Dict("message" => "hello world", "animal" => Animal(1, "cat", "whiskers"))
    end
)

Api.start()