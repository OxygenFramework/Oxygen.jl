module CronDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using Dates

# You can use the @cron macro directly 

@cron "*/2" function()
    println("every 2 seconds")
end

@cron "*/5" function every5seconds()
    println("every 5 seconds")
end

value = 0

# You can also just use the 'cron' keyword that's apart of the router() function
@get router("/increment", cron="*/11", interval=4) function()
    global value += 1
    return value
end

@get router("/getvalue") function()
    return value
end

# all endpoints will inherit this cron expression
pingpong = router("/pingpong", cron="*/3")

@get pingpong("/ping") function()
    println("ping")
    return "ping"
end

# here we override the inherited cron expression
@get pingpong("/pong", cron="*/7") function()
    println("pong")
    return "pong"
end

@get "/home" function()
    "home"
end

serve()

end