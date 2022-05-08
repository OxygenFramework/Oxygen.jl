include("../src/FastApiJL.jl")
import .FastApiJL
import HTTP

local Api = FastApiJL

Api.@get "/bah" function (req::HTTP.Request)
    return "wow"
end

Api.@get "/test" function (req::HTTP.Request)
    return "test"
end

Api.start()
