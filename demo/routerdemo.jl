module RouterDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using StructTypes
using JSON3

base = "/hello"
hellorouter = router(base, tags=["greeting"])
repeat = router("/repeat", interval = 10, tags=["repeat"])
emptyrouter = router()

@get "/nice" function(req)
    return "nice"
end

@get hellorouter("/nice", tags=["cool"]) function(req)
    return "nice"
end

@get hellorouter("/other") function(req)
    return "other"
end

@get emptyrouter("/empty", interval = 3) function(req)
    println("empty")
    return "empty"
end

@get emptyrouter("/basic", interval = 0.5) function(req)
    println("basic")
    return "basic"
end

@get repeat("/one") function(req)
    println("one")
    return "one"
end


@get "$base/cool" function(req)
    return "cool"
end

serve()

end