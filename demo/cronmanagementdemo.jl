module CronManagementDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using Dates

get("/data") do
    Dict("value" => 3)
end

get("/hello") do
    Dict("msg" => "hello world")
end

function logtime()
    @info "current time: $(now())"
end

# initialize the app with an already running cron job
# @cron "*" logtime


get("/error") do
    "a" + 3
end

get("/long") do
    sleep(0.1)
end

get("/register") do
    @info "registering new job"
    @cron "*/2" logtime
    "registered jobs"
end

get("/start") do
    @info "/start POST endpoint hit; running job"
    startcronjobs()
    "started jobs"
end

get("/clear") do 
    @info "clearing jobs"
    clearcronjobs()
    "cleared jobs"
end

get("/stop") do
    @info "/stop POST endpoint hit"
    stopcronjobs()
    "stopped jobs"
end

@info "Starting server"
serve()
@info "Server stopped"

end