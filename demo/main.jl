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

Api.@get "/bah" function (req::HTTP.Request)
    return "wow"
end

Api.@get "/test" function (req::HTTP.Request)
    return 77.88
end

Api.@get("/multi",
    function (req::HTTP.Request)
        return Dict("message" => "hello world", "animal" => JSON3.write(Animal(1, "feline", "whiskers")))
    end
)

Api.start()