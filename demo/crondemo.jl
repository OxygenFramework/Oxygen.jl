module CronDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP

value = 0

# Here's utility macro to call functions directly
@cron "*/5" function()
    println("every 5 seconds")
end

# You can also just use the 'cron' keyword that's apart of the router() function
@get router("/increment", cron="*/3") function()
    global value += 1
    println(value)
    return value
end

serve()

end