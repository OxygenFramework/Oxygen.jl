module CronManagementTests

using Test
using Oxygen; @oxidise

const iterations = Ref{Int}(0)

get(router("/three", cron="*/3")) do 
    iterations[] += 1
end

@cron "*/2" function()
    iterations[] += 1
end

# make sure we can see errors in the logs
@cron "*/3" function()
    throw("Here's a custom error")
end

@cron "*/5" function()
    iterations[] += 1
end

startcronjobs()
startcronjobs() # all active cron jobs should be filtered out and not started again

# register a new cron job after the others have already began
@cron "*/4" function()
    iterations[] += 1
end

startcronjobs()

while iterations[] < 15
    sleep(1)
end

stopcronjobs()
clearcronjobs()

end