module CronManagementDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using Dates

get("/data") do
    Dict("msg" => "hello")
end

taskrouter = router("/tasks", tags=["tasks"])
cronrouter = router("/cron", tags=["cron"])

@get(taskrouter("/start")) do
    starttasks()
    "started tasks"
end

@get(taskrouter("/stop")) do
    stoptasks()
    "stopped tasks"
end

@get(taskrouter("/clear")) do
    cleartasks()
    "cleared tasks"
end

get(router("/task", interval=3.5)) do 
    println("repeat task")
end

# function logtime()
#     @info "current time: $(now())"
# end

# # initialize the app with an already running cron job
# @cron "*" logtime

# get(cronrouter("/register")) do
#     @info "registering new job"
#     @cron "*/2" logtime
#     "registered jobs"
# end

# get(cronrouter("/start")) do
#     @info "/start POST endpoint hit; running job"
#     startcronjobs()
#     "started jobs"
# end

# get(cronrouter("/clear")) do 
#     @info "clearing jobs"
#     clearcronjobs()
#     "cleared jobs"
# end

# get(cronrouter("/stop")) do
#     @info "/stop POST endpoint hit"
#     stopcronjobs()
#     "stopped jobs"
# end


try 
    serve()
finally 
    terminate()
end

end