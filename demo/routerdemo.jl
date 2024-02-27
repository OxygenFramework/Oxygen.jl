module RouterDemo 

using Oxygen
using HTTP
using JSON3

hellorouter = router("/hello", tags=["greeting"])

@get hellorouter("/excited", tags=["good"]) function(req)
    return "excited"
end

@get hellorouter("/sad") function(req)
    return "sad"
end

repeat = router("/repeat", interval = 1, tags=["repeat"])

@get repeat("/one") function(req)
    println("one")
    return "one"
end

emptyrouter = router()

@get emptyrouter("/empty", interval = 3) function(req)
    println("empty")
    return "empty"
end

# you can also pass the `router()` function itself
@get router("/spam", tags=["spam"], interval=0.25) function()
    println("spam")
end

serve()

end