module RouterDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using StructTypes
using JSON3

base = "/hello"
helloroute = router(base, tags=["greeting"])

function getthing()
    return "wow"
end

@get getthing() function(req)
    return "nice"
end

@get helloroute("/asdf", pathtags=["cool"]) function(req)
    return "nice"
end

@get helloroute("/other") function(req)
    return "other"
end

@get "$base/cool" function(req)
    return "cool"
end

serve()

end