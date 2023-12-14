module CronIssue 


include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using Dates


function run_job(req)
    @info "$(now())"
    return 1
end

@get "/data" function ()
    Dict("msg" => "hello")
end


@get "/start" function (req::HTTP.Request)
    @info "/start POST endpoint hit; running job"
    stopcronjobs()

    @cron "*" function ()
        run_job(req)
    end

    startcronjobs()
    out = run_job(req)
    return out
end


@get "/stop" function (req::HTTP.Request)
    @info "/stop POST endpoint hit"
    stopcronjobs()
    "stopped"
end


@info "Starting server"
serve()

@info "Server stopped"

end