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

@cron "*/5" function()
    iterations[] += 1
end

startcronjobs()

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