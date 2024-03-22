module WebSocketDemo
using HTTP
using HTTP.WebSockets: send

include("../src/Oxygen.jl")
using .Oxygen

@get "/" function()
    text("hello world")
end

@ws "/ws" function(ws::HTTP.WebSocket)
    for msg in ws
        @info "Received message: $msg"
        send(ws, msg)
    end
end

@ws "/ws/args/{x}" function(ws::HTTP.WebSocket, x::Int)
    println("Connected to websocket with x = $x")
    for msg in ws
        @info "Received message from $x: $msg"
        send(ws, msg)
    end
end

serve()

end