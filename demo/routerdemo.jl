module RouterDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using StructTypes
using JSON3

base = "/hello"
hellorouter = router(base, tags=["greeting"])

function getthing()
    return "wow"
end

@get getthing() function(req)
    return "nice"
end

@get hellorouter("/asdf", pathtags=["cool"]) function(req)
    return "nice"
end

@get hellorouter("/other") function(req)
    return "other"
end

@get "$base/cool" function(req)
    return "cool"
end

serve()

end