module RepeatTasks
using HTTP
using ..Core: TasksRuntime

export starttasks, stoptasks, cleartasks

"""
    starttasks()

Start all background repeat tasks
"""
function starttasks(tasks::TasksRuntime)

    # exit function early if no tasks are register
    if isempty(tasks.registeredtasks)
        return
    end

    println()
    printstyled("[ Starting $(length(tasks.registeredtasks)) Repeat Task(s)\n", color = :magenta, bold = true)  
    
    for (action, task) in tasks.registeredtasks
        path, httpmethod, interval = task
        message = "method: $httpmethod, path: $path, interval: $interval seconds"
        printstyled("[ Task: ", color = :magenta, bold = true)  
        println(message)
        timer = Timer(action, 0, interval=interval)
        push!(tasks.timers, timer)   
    end

end 

"""
    stoptasks()

Stop all background repeat tasks
"""
function stoptasks(tasks::TasksRuntime)
    for timer in tasks.timers
        if isopen(timer)
            close(timer)
        end
    end
    empty!(tasks.timers)
end


"""
    cleartasks(ct::Context)

Clear any stored repeat task definitions
"""
function cleartasks(tasks::TasksRuntime)
    empty!(tasks.repeattasks)
end


end