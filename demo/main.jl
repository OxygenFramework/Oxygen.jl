include("../src/FastApiJL.jl")
import .FastApiJL
import HTTP
import JSON3

Api = FastApiJL

Api.@get "/bah" function (req::HTTP.Request)
    return "wow"
end

Api.@get "/test" function (req::HTTP.Request)
    return 77.88
end

Api.@get("/multi",
    function (req::HTTP.Request)
        return Dict("message" => "hello world")
    end
)

Api.start()