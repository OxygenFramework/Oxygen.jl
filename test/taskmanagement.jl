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

# this should do nothing because the tasks aren't registered yet
starttasks()

serve(async=true, show_banner=false)

while iterations[] < 10
    sleep(1)
end

terminate()

end