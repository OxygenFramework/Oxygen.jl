module RepeatTasks
using HTTP
using ..Core

export starttasks, stoptasks, cleartasks

"""
    starttasks()

Start all background repeat tasks
"""
function starttasks(ctx::Context)

    # exit function early if no tasks are register
    if isempty(ctx.tasks.repeattasks)
        return
    end

    println()
    printstyled("[ Starting $(length(ctx.tasks.repeattasks)) Repeat Task(s)\n", color = :magenta, bold = true)  
    
    for task in ctx.tasks.repeattasks
        path, httpmethod, interval = task
        message = "method: $httpmethod, path: $path, interval: $interval seconds"
        printstyled("[ Task: ", color = :magenta, bold = true)  
        println(message)
        action = (timer) -> internalrequest(ctx, HTTP.Request(httpmethod, path))
        timer = Timer(action, 0, interval=interval)
        push!(ctx.tasks.timers, timer)   
    end

end 

"""
    stoptasks()

Stop all background repeat tasks
"""
function stoptasks(ctx::Context)
    for timer in ctx.tasks.timers
        if isopen(timer)
            close(timer)
        end
    end
    empty!(ctx.tasks.timers)
end


"""
    cleartasks(ct::Context)

Clear any stored repeat task definitions
"""
function cleartasks(ctx::Context)
    empty!(ctx.tasks.repeattasks)
end


end