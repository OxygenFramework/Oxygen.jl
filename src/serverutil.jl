module ServerUtil

using HTTP 
using Sockets 
using JSON3

export ROUTER, server, serve, serveparallel, terminate, internalrequest, DefaultHandler

# define REST endpoints to dispatch to "service" functions
const ROUTER = HTTP.Router()
const server = Ref{Union{Sockets.TCPServer, Nothing}}(nothing) 

"""
    serve(host="127.0.0.1", port=8080; kwargs...)

Start the webserver with the default request handler
"""
function serve(host="127.0.0.1", port=8080; kwargs...)
    println("Starting server: http://$host:$port")
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    HTTP.serve(req -> DefaultHandler(req), host, port; server=server[], kwargs...)
end


"""
    serve(handler::Function, host="127.0.0.1", port=8080; kwargs...)

Start the webserver with your own custom request handler
"""
function serve(handler::Function, host="127.0.0.1", port=8080; kwargs...)
    println("Starting server: http://$host:$port")
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    HTTP.serve(req -> handler(req, ROUTER, DefaultHandler), host, port; server=server[], kwargs...)
end


"""
    serveparallel(host="127.0.0.1", port=8080, queuesize=1024; kwargs...)

Starts the webserver in streaming mode and spawns n - 1 worker threads to process individual requests.
A Channel is used to schedule individual requests in FIFO order. Requests in the channel are
then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(host="127.0.0.1", port=8080, queuesize=1024; kwargs...)
    println("Starting server: http://$host:$port")
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    StreamUtil.start(server[], req -> DefaultHandler(req); queuesize=queuesize, kwargs...)
end


"""
    serveparallel(handler::Function, host="127.0.0.1", port=8080, queuesize=1024; kwargs...)

Starts the webserver in streaming mode with your own custom request handler and spawns n - 1 worker 
threads to process individual requests. A Channel is used to schedule individual requests in FIFO order. 
Requests in the channel are then removed & handled by each the worker threads asynchronously. 
"""
function serveparallel(handler::Function, host="127.0.0.1", port=8080, queuesize=1024; kwargs...)
    println("Starting server: http://$host:$port")
    server[] = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))
    StreamUtil.start(server[], req -> handler(req, ROUTER, DefaultHandler); queuesize=queuesize, kwargs...)
end


"""
    terminate()

stops the webserver immediately
"""
function terminate()
    if !isnothing(server[]) && isopen(server[])
        close(server[])
    end
end


"""
    internalrequest(request::HTTP.Request)

Directly call one of our other endpoints registered with the router
"""
function internalrequest(req::HTTP.Request) :: HTTP.Response
    return DefaultHandler(req)
end


function DefaultHandler(req::HTTP.Request)
    try
        response_body = HTTP.handle(ROUTER, req)
        # if a raw HTTP.Response object is returned, then don't do any extra processing on it
        if isa(response_body, HTTP.Messages.Response)
            return response_body 
        elseif isa(response_body, String)
            headers = ["Content-Type" => HTTP.sniff(response_body)]
            return HTTP.Response(200, headers , body=response_body)
        else 
            body = JSON3.write(response_body)
            headers = ["Content-Type" => "application/json; charset=utf-8"]
            return HTTP.Response(200, headers , body=body)
        end 
    catch error
        @error "ERROR: " exception=(error, catch_backtrace())
        return HTTP.Response(500, "The Server encountered a problem")
    end
end


end