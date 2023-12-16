module CronManagementDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using Dates

get("/data") do
    Dict("msg" => "hello")
end

function logtime()
    @info "current time: $(now())"
end

@cron "*" logtime

get("/register") do
    @info "registering jobs"
    @cron "*/2" function()
        @info "current time: $(now())"
    end
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