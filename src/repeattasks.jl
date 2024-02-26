module RepeatTasks
using HTTP
using ..Core: TasksContext, RegisteredTask, TaskDefinition, ActiveTask

export starttasks, stoptasks, cleartasks, task

"""
Create a repeat task and register it with the tasks context
"""
function task(repeattasks::Set{RegisteredTask}, interval::Real, name::String, f::Function)
    task_id = hash((name, interval, f))
    task = RegisteredTask(task_id, name, interval, f)
    push!(repeattasks, task)
end

"""
    starttasks()

Start all background repeat tasks
"""
function starttasks(tasks::TasksContext)

    # exit function early if no tasks are register
    if isempty(tasks.registered_tasks)
        return
    end

    # pull out all ids for the current running tasks
    running_tasks = Set{UInt}(task.id for task in tasks.active_tasks)

    # filter out any tasks that are already running
    filtered_tasks = filter(tasks.registered_tasks) do repeattask
        if repeattask.id in running_tasks
            printstyled("[ Task: $(repeattask.name) is already running\n", color = :yellow)
            return false
        else
            return true
        end
    end

    # exit function early if no tasks to start
    if isempty(filtered_tasks)
        return
    end

    # Start any remaining tasks
    println()
    printstyled("[ Starting $(length(filtered_tasks)) Repeat Task(s)\n", color = :magenta, bold = true)  
    
    for task in filtered_tasks
        printstyled("[ Task: ", color = :magenta, bold = true)  
        println("{ interval: $(task.interval) seconds, name: $(task.name) }")

        action = (timer) -> task.action()
        timer = Timer(action, 0, interval=task.interval)
        push!(tasks.active_tasks, ActiveTask(task.id, timer))
    end

end 

"""
    stoptasks()

Stop all background repeat tasks
"""
function stoptasks(tasks::TasksContext)
    for task in tasks.active_tasks
        if isopen(task.timer)
            close(task.timer)
        end
    end
    empty!(tasks.active_tasks)
end


"""
    cleartasks(ct::Context)

Clear any stored repeat task definitions
"""
function cleartasks(tasks::TasksContext)
    empty!(tasks.registered_tasks)
end


end