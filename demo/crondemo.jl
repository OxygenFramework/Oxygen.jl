module CronDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP


value = 0

@get "/increment" function(req)
    global value += 1
    return value
end

serve()

end