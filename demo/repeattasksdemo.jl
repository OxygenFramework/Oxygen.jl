module RepeatTasksDemo

include("../src/Oxygen.jl")
using .Oxygen

const iterations = Ref{Int}(0)

get(router("/one", interval=1)) do 
    iterations[] += 1
end

get(router("/two", interval=2)) do 
    iterations[] += 1
end

@repeattask 3 function()
    iterations[] += 1
end

@repeattask 4 "every 4 seconds" function()
    iterations[] += 1
end

starttasks()

while iterations[] < 10
    println("Iterations: ", iterations[])
    sleep(1)
end

stoptasks()
cleartasks()


end