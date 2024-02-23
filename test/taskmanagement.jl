module TaskManagementTests

using Test
using Oxygen; @oxidise

const iterations = Ref{Int}(0)

get(router("/one", interval=1)) do 
    iterations[] += 1
end

get(router("/three", interval=3)) do 
    iterations[] += 1
end

@repeattask 3 function()
    iterations[] += 1
end

@repeattask 4 "every 4 seconds" function()
    iterations[] += 1
end

starttasks()

while iterations[] < 15
    sleep(1)
end

terminate()

end