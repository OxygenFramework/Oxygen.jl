# This module was adapted from this dicussion
# https://discourse.julialang.org/t/http-jl-doesnt-seem-to-be-good-at-handling-over-1k-concurrent-requests-in-comparison-to-an-alternative-in-python/38281/16
module StreamUtil
using Sockets
using HTTP

export start, stop

struct WebRequest
    http::HTTP.Stream
    done::Threads.Event
end

struct Handler
    queue::Channel{WebRequest}
    count::Threads.Atomic{Int}
    shutdown::Threads.Atomic{Bool}
    Handler( queuesize = 1024 ) = begin
        new(Channel{WebRequest}(queuesize), Threads.Atomic{Int}(0), Threads.Atomic{Bool}(false))
    end
end

global const HANDLER = Ref{Handler}(Handler())

"""
This function is run in each spawned worker thread, which removes queued requests & handles them asynchronously
"""
function respond(h::Handler, handleReq::Function)
    @info "Started Worker Thread ~ id: $(Threads.threadid())"
    streamhandler = HTTP.Handlers.streamhandler(handleReq)
    while h.shutdown[] == false
        task = take!(h.queue)
        Threads.atomic_sub!(h.count, 1)
        @async begin
            try
                streamhandler(task.http)
            catch error 
                @error "ERROR: " exception=(error, catch_backtrace())
                HTTP.setstatus(task.http, 500)
                write(task.http, "The Server encountered a problem")
            finally
                notify(task.done)
            end
        end
    end
end

"""
Shutdown the handler
"""
function stop()
    # toggle the shutdown flag
    HANDLER[].shutdown[] = true
    # close the Channel
    close(HANDLER[].queue)
end


"""
Starts the webserver in streaming mode and spaws n - 1 worker threads to start processing incoming requests
"""
function start(handleReq::Function; host="127.0.0.1", port=8080, queuesize = 1024, kwargs...)
    
    # reset handler on startup
    HANDLER[] = Handler()
    local handler = HANDLER[]
    local nthreads = Threads.nthreads() - 1

    if nthreads <= 0
        throw("This process needs more than one thread to run tasks on. For example, launch julia like this: julia --threads 4") 
    end

    for i in 1:nthreads
        @Threads.spawn respond(handler, handleReq)
    end

    function streamhandler(stream::HTTP.Stream)
        try
            if handler.count[] < queuesize
                Threads.atomic_add!(handler.count, 1)
                local request = WebRequest(stream, Threads.Event())
                put!(handler.queue, request)
                wait(request.done)
            else
                @warn "Dropping connection..."
                HTTP.setstatus(stream, 500)
                write(stream, "Server overloaded.")
            end 
        catch e
            @error "ERROR: " exception=(e, catch_backtrace())
            HTTP.setstatus(stream, 500)
            write(stream, "The Server encountered a problem")
        end
    end

    return HTTP.serve!(streamhandler, host, port; stream=true, kwargs...) 

end

end