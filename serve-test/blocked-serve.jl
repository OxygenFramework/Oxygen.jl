using Base.Threads
using Infiltrator
using Revise
using Oxygen
using HTTP
ENV["JULIA_DEBUG"] = "Oxygen"

# Run this with -t 1,1

println("$(nthreadpools()) threadpools. default=$(nthreads(:default)) interactive=$(nthreads(:interactive))")

function block(n::Int)
    start_time = time()
    while (time() - start_time) < n
    end
    return "Blocking complete after $n seconds"
end


@get "/health" function()
    @info "entered /health threadid=$(Threads.threadid())"
    json(Dict(:status => "healthy"))
end

@get "/block" function ()
    block_time = 10
    @info "blocking for $block_time seconds. threadid=$(Threads.threadid())"
    # using block because sleep() would yield
    block(block_time)
    @info "done blocking threadid=$(Threads.threadid())"
    text("done")
end

@get "/throw" function()
    throw(
        ErrorException("error from route impl")
    )
end

function start()
    serveparallel(
        is_prioritized = (req::HTTP.Request) -> req.target == "/health"
    )
end

start()
