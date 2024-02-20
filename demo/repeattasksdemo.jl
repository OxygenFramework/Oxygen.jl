module RepeatTasksDemo

using Oxygen

const iterations = Ref{Int}(0)

get(router("/one", interval=1)) do 
    iterations[] += 1
    println("one")
end

get(router("/three", interval=3)) do 
    iterations[] += 1
    println("three")
end

serve(async=true)


while iterations[] < 10
    println("Iterations: ", iterations[])
    sleep(1)
end

terminate()


end