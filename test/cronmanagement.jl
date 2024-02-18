module CronManagementTests

using Test
using Oxygen; @oxidise

const iterations = Ref{Int}(0)

function register()
    @cron "*/2" function()
        iterations[] += 1
    end

    @cron "*/5" function()
        iterations[] += 1
    end
end

register()
startcronjobs()

while iterations[] < 10
    sleep(1)
end

stopcronjobs()
clearcronjobs()

end