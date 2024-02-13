module ParallelDemo 
    using Oxygen
    using HTTP
    using JSON3
    using StructTypes
    using SwaggerMarkdown
    using Base.Threads

    ############## Atomic variable example ##############

    StructTypes.StructType(::Type{Atomic{Int64}}) = StructTypes.Struct()

    x = Atomic{Int64}(0);
    
    @get "/atomic/show" function(req)
        return x
    end

    @get "/atomic/increment" function()
        atomic_add!(x, 1)
        return x
    end

    ############## ReentrantLock example ##############

    global a = 0
    rl = ReentrantLock()

    @get "/lock/show" function()
        return a
    end

    @get "/lock/increment" function()
        lock(rl)
        try
            global a
            a += 1
        finally
            unlock(rl)
        end
        return a
    end

    # start the web server in parallel mode
    serveparallel()

end
