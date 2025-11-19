module TaskManagementTests

using Test
using Oxygen; @oxidize

const iterations = Ref{Int}(0)

get(router("/one", interval=1)) do 
    iterations[] += 1
end

get(router("/three", interval=3)) do 
    iterations[] += 1
end

@repeat 3.4 function()
    iterations[] += 1
end

@repeat 4 "every 4 seconds" function()
    iterations[] += 1
end

starttasks()
starttasks() # all active tasks should be filtered out and not started again

# register a new task after the others have already began
@repeat 5 function()
    iterations[] += 1
end

starttasks()

while iterations[] < 15
    sleep(1)
end

terminate()

end