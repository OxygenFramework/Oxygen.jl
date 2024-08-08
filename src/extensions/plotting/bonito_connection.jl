using HTTP.WebSockets: WebSocket, WebSocketError
using HTTP.WebSockets: receive, isclosed
using HTTP.WebSockets

import .Bonito: setup_connection
using .Bonito
using .Bonito: FrontendConnection, Websocket, process_message, save_read, save_write, Session, js_str

export OxygenWebSocketConnection, bonito_websocket_handler

mutable struct OxygenWebSocketConnection <: FrontendConnection
    endpoint::String
    socket::Union{Nothing,WebSocket}
    lock::ReentrantLock
    session::Union{Nothing,Session}
end

const open_connections = Dict{String, Session{OxygenWebSocketConnection}}()
const open_connections_lock = ReentrantLock()

function OxygenWebSocketConnection(endpoint::String)
    return OxygenWebSocketConnection(endpoint, nothing, ReentrantLock(), nothing)
end

function Base.isopen(ws::OxygenWebSocketConnection)
    isnothing(ws.socket) && return false
    # isclosed(ws.socket) returns readclosed && writeclosed
    # but we consider it closed if either is closed?
    if ws.socket.readclosed || ws.socket.writeclosed
        return false
    end
    # So, it turns out, ws connection where the tab gets closed
    # stay open indefinitely, but aren't writable anymore
    # TODO, figure out how to check for that
    return true
end

function Base.write(ws::OxygenWebSocketConnection, binary)
    if isnothing(ws.socket)
        error("socket closed or not opened yet")
    end
    lock(ws.lock) do
        written = save_write(ws.socket, binary)
        if written != true
            @debug "couldnt write, closing ws"
            close(ws)
        end
    end
end

function Base.close(ws::OxygenWebSocketConnection)
    isnothing(ws.socket) && return
    try
        socket = ws.socket
        ws.socket = nothing
        isclosed(socket) || close(socket)
    catch e
        if !WebSockets.isok(e)
            @warn "error while closing websocket" exception=(e, Base.catch_backtrace())
        end
    end
end

#@websocket "/bonito/{session_id}" function(websocket::HTTP.WebSocket, session_id::String)
#Oxygen.Core.register(CONTEXT[], WEBSOCKET, path, func)
function bonito_websocket_handler(websocket::HTTP.WebSocket, session_id::String)
    session = nothing
    lock(open_connections_lock) do 
        session = open_connections[session_id]
    end
    connection = session.connection
    lock(connection.lock) do
        connection.socket = websocket
    end

    # the channel is used so that we can do async processing of messages
    # While still keeping the order of messages
    @debug("opening ws connection for session: $(session.id)")
    while !isclosed(websocket)
        bytes = save_read(websocket)
        # nothing means the browser closed the connection so we're done
        isnothing(bytes) && break
        try
            process_message(session, bytes)
        catch e
            # Only print any internal error to not close the connection
            @warn "error while processing received msg" exception = (e, Base.catch_backtrace())
        end
    end
end


function setup_connection(session::Session{OxygenWebSocketConnection})
    session_id = session.id
    lock(open_connections_lock) do 
        open_connections[session_id] = session
    end
    proxy_url = session.connection.endpoint
    return js"""
        $(Websocket).then(WS => {
            WS.setup_connection({proxy_url: $(proxy_url), session_id: $(session.id), compression_enabled: $(session.compression_enabled)})
        })
    """
end
