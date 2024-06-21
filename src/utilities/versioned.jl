
export @get_pool_counts, @get_pool_size, @adaptive_spawn

"""
Helper function used to determine which threadpool to use based on the available resources.
"""
macro get_threadpool()
    if VERSION >= v"1.9"
        :(Threads.nthreads(:default) >= Threads.nthreads(:interactive) ? :default : :interactive)  
    else
        :(:default)
    end
end

"""
Returns the total number of threads available across both threadpools
"""
macro get_pool_size() 
    if VERSION >= v"1.9"
        return :(Threads.nthreads(:default) + Threads.nthreads(:interactive))
    else
        return :(Threads.nthreads())
    end
end

"""
Return the number of available threads in each threadpool as a tuple in the following 
format: (default, interactive)
"""
macro get_pool_counts() 
    if VERSION >= v"1.9"
        return quote 
            (;default=Threads.nthreads(:default), interactive=Threads.nthreads(:interactive))
        end
    else
        return quote 
            (;default=Threads.nthreads(), interactive=0)
        end
    end
end

"""
If we are running in parallel mode, we need to use the `@adaptive_spawn` macro to schedule 
tasks on whichever threadpool that has more resources available (:default vs :interactive).

- If a non-null threadpool is provided, we use that threadpool instead.
- In the case of a tie, we default to the :default threadpool.
"""
macro adaptive_spawn(defaultpool, f) 
    if VERSION >= v"1.9"
        thread_pool = isnothing(defaultpool) ? @get_threadpool() : defaultpool
        return :(Threads.@spawn $thread_pool $f) |> esc
    else
        return :(Threads.@spawn $f) |> esc
    end
end