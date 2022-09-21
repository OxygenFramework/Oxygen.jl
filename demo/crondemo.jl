module CronDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP

value = 0

@cron "*/5" function()
    println("every 5 seconds")
end

@get router("/increment", cron="*/3") function()
    global value += 1
    println(value)
    return value
end

serve()

end