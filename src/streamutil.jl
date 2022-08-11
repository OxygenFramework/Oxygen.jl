# This module was adapted from this dicussion
# https://discourse.julialang.org/t/http-jl-doesnt-seem-to-be-good-at-handling-over-1k-concurrent-requests-in-comparison-to-an-alternative-in-python/38281/16
module StreamUtil
using Sockets
using HTTP

export start

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
function respond(h::Handler, handleReq::Function)
    @info "Started Worker Thread ~ id: $(Threads.threadid())"
    while h.shutdown[] == false
        request = take!(h.queue)
        Threads.atomic_sub!(h.count, 1)
        @async begin
            try 
                # read all buffered data from stream
                body::Vector{UInt8} = []
                while !eof(request.http)
                    push!(body, readavailable(request.http)...)
                end

                # get request from stream 
                message::HTTP.Request = request.http.message

                # rebuild request object with body
                req = HTTP.Request(
                    message.method, 
                    message.target,
                    message.headers,
                    body;
                    version=message.version,
                    parent=message.parent
                )

                # process request
                response::HTTP.Response = handleReq(req)

                # write response back to stream
                HTTP.setstatus(request.http, response.status)

                # add all headers from response 
                for (k,v) in response.headers
                    HTTP.setheader(request.http, k => v)
                end

                write(request.http, isempty(response.body) ? " " : response.body)
            catch error 
                @error "ERROR: " exception=(error, catch_backtrace())
                HTTP.setstatus(request.http, 500)
                write(request.http, "The Server encountered a problem")
            finally
                notify(request.done)
            end

        end
    end
end

"""
Starts the webserver in streaming mode and spaws n - 1 worker threads to start processing incoming requests
"""
function start(server::Sockets.TCPServer, handleReq::Function; queuesize = 1024, kwargs...)
    local handler = Handler()
    local nthreads = Threads.nthreads() - 1

    if nthreads <= 0
        throw("This process needs more than one thread to run tasks on. For example, launch julia like this: julia --threads 4") 
    end

    for i in 1:nthreads
        @Threads.spawn respond(handler, handleReq)
    end

    try
        HTTP.serve(;server = server, stream = true, kwargs...) do stream::HTTP.Stream  
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
    finally
        close(server)
        handler.shutdown[] = true
    end

end

end