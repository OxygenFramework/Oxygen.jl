# This module was adapted from this dicussion
# https://discourse.julialang.org/t/http-jl-doesnt-seem-to-be-good-at-handling-over-1k-concurrent-requests-in-comparison-to-an-alternative-in-python/38281/16
module ChannelsAsync
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
        Handler( size = 1024 ) = begin
            new(Channel{WebRequest}(size), Threads.Atomic{Int}(0), Threads.Atomic{Bool}(false))
        end
    end

    function respond(h::Handler, handleReq::Function)
        @info "Started thread: $(Threads.threadid())"
        while h.shutdown[] == false
            request = take!(h.queue)
            Threads.atomic_sub!(h.count, 1)
            @async begin

                # read all buffered data from stream
                while !eof(request.http)
                    readavailable(request.http)
                end

                # process request
                response::HTTP.Response = handleReq(request.http.message)

                # set all the headers from the response to the stream
                for (k,v) in response.headers
                    HTTP.setheader(request.http, k => v)
                end

                HTTP.setstatus(request.http, response.status)
                write(request.http, response.body)
                notify(request.done)
            end
        end
    end


    function start(server::Sockets.TCPServer, handleReq::Function; size = 1024, kwargs...)
        local handler = Handler()
        local nthreads = Threads.nthreads() - 1

        if nthreads == 0
            throw("This process needs more than one thread to run tasks on. For example, launch julia like this: julia --threads 4") 
        end

        for i in 1:nthreads
            @Threads.spawn respond(handler, handleReq)
        end

        try
            HTTP.serve(;server = server, stream = true, kwargs...) do stream::HTTP.Stream  
                try
                    if handler.count[] < size
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