using HTTP.WebSockets: WebSocket, WebSocketError
using HTTP.WebSockets: receive, isclosed
using HTTP.WebSockets

import .Bonito: setup_connection
using .Bonito
using .Bonito: FrontendConnection, WebSocketHandler, Session, setup_websocket_connection_js, run_connection_loop

export OxygenWebSocketConnection, bonito_websocket_handler

mutable struct OxygenWebSocketConnection <: FrontendConnection
    endpoint::String
    session::Union{Nothing,Session}
    handler::WebSocketHandler
end

const open_connections = Dict{String, Session{OxygenWebSocketConnection}}()
const open_connections_lock = ReentrantLock()

function OxygenWebSocketConnection(endpoint::String)
    return OxygenWebSocketConnection(endpoint, nothing, WebSocketHandler())
end

Base.isopen(ws::OxygenWebSocketConnection) = isopen(ws.handler)
Base.write(ws::OxygenWebSocketConnection, binary) = write(ws.handler, binary)
Base.close(ws::OxygenWebSocketConnection) = close(ws.handler)

#@websocket "/bonito/{session_id}" function(websocket::HTTP.WebSocket, session_id::String)
#Oxygen.Core.register(CONTEXT[], WEBSOCKET, path, func)
function bonito_websocket_handler(websocket::HTTP.WebSocket, session_id::String)
    session = nothing
    lock(open_connections_lock) do 
        session = open_connections[session_id]
    end
    handler = session.connection.handler

    # the channel is used so that we can do async processing of messages
    # While still keeping the order of messages
    @debug("opening ws connection for session: $(session.id)")
    run_connection_loop(session, handler, websocket)
end


function setup_connection(session::Session{OxygenWebSocketConnection})
    session_id = session.id
    lock(open_connections_lock) do 
        open_connections[session_id] = session
    end
    external_url = session.connection.endpoint
    return setup_websocket_connection_js(external_url, session)
end
