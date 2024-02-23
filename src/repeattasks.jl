module RepeatTasks
using HTTP
using ..Core: TasksContext

export starttasks, stoptasks, cleartasks, task

"""
Create a repeat task and register it with the tasks context
"""
function task(repeattasks::Set, interval::Real, name::String, f::Function)
    task_definition = (name, interval, f)
    task_id = hash(task_definition)
    task = (task_id, name, interval)
    push!(repeattasks, (f, task))
end

"""
    starttasks()

Start all background repeat tasks
"""
function starttasks(tasks::TasksContext)

    # exit function early if no tasks are register
    if isempty(tasks.repeattasks)
        return
    end

    println()
    printstyled("[ Starting $(length(tasks.repeattasks)) Repeat Task(s)\n", color = :magenta, bold = true)  
    
    for (func, task) in tasks.repeattasks
        action = (timer) -> func()
        task_id, name, interval = task

        printstyled("[ Task: ", color = :magenta, bold = true)  
        println("{ interval: $(interval) seconds, name: $name }")

        timer = Timer(action, 0, interval=interval)
        push!(tasks.timers, timer)
    end

end 

"""
    stoptasks()

Stop all background repeat tasks
"""
function stoptasks(tasks::TasksContext)
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
function cleartasks(tasks::TasksContext)
    empty!(tasks.repeattasks)
end


end