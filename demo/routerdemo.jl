module RouterDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using StructTypes
using JSON3

repeat = router("/repeat", interval = 1, tags=["repeat"])
hellorouter = router("/hello", tags=["greeting"])
emptyrouter = router()

function blah()
    return "/test/"
end

@get router("/spam", tags=["spam"], interval=0.25) function()
    println("spam")
end

@get hellorouter("/nice", tags=["good"]) function(req)
    return "nice"
end

@get hellorouter("/other") function(req)
    return "other"
end

@get emptyrouter("/empty", interval = 3) function(req)
    println("empty")
    return "empty"
end

@get repeat("/one") function(req)
    println("one")
    return "one"
end

serve()

end