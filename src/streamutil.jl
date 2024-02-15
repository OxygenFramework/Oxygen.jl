# This module was adapted from this dicussion
# https://discourse.julialang.org/t/http-jl-doesnt-seem-to-be-good-at-handling-over-1k-concurrent-requests-in-comparison-to-an-alternative-in-python/38281/16
module StreamUtil
using Sockets
using HTTP

export start, stop, Handler

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


"""
This function is run in each spawned worker thread, which removes queued requests & handles them asynchronously
"""
function respond(h::Handler, handle_stream::Function)
    @info "Started Worker Thread ~ id: $(Threads.threadid())"
    while h.shutdown[] == false
        task = take!(h.queue)
        Threads.atomic_sub!(h.count, 1)
        @async begin
            try
                handle_stream(task.http)
            finally
                notify(task.done)
            end
        end
    end
end

"""
Shutdown the handler
"""
function stop(handler::Handler)
    # toggle the shutdown flag
    handler.shutdown[] = true
    if isopen(handler.queue)
        # close the Channel
        close(handler.queue)
    end
end


"""
Starts the webserver in streaming mode and spaws n - 1 worker threads to start processing incoming requests
"""
function start(handler::Handler, handle_stream::Function; host="127.0.0.1", port=8080, queuesize = 1024, kwargs...)
    
    local nthreads = Threads.nthreads() - 1

    if nthreads <= 0
        throw("This process needs more than one thread to run tasks on. For example, launch julia like this: julia --threads 4") 
    end

    for i in 1:nthreads
        @Threads.spawn respond(handler, handle_stream)
    end

    function streamhandler(stream::HTTP.Stream)
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
    end

    return HTTP.serve!(streamhandler, host, port; stream=true, kwargs...) 

end

end
