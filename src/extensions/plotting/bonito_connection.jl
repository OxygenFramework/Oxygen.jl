using HTTP.WebSockets: WebSocket, WebSocketError
using HTTP.WebSockets: receive, isclosed
using HTTP.WebSockets

import .Bonito: setup_connection
using .Bonito: FrontendConnection, WebSocketHandler, Session, setup_websocket_connection_js, run_connection_loop, force_connection!

export OxygenWebSocketConnection, mk_bonito_websocket_handler, setup_bonito_connection

mutable struct OxygenWebSocketConnection <: FrontendConnection
    context::Context
    endpoint::String
    session::Union{Nothing,Session}
    handler::WebSocketHandler
end

function OxygenWebSocketConnection(context::Context, endpoint::String)
    return OxygenWebSocketConnection(context, endpoint, nothing, WebSocketHandler())
end

Base.isopen(ws::OxygenWebSocketConnection) = isopen(ws.handler)
Base.write(ws::OxygenWebSocketConnection, binary) = write(ws.handler, binary)
Base.close(ws::OxygenWebSocketConnection) = close(ws.handler)

mutable struct BonitoConnectionContext
    open_connections::Dict{String, Session{OxygenWebSocketConnection}}
    open_connections_lock::ReentrantLock
end

BonitoConnectionContext() = BonitoConnectionContext(Dict{String, Session{OxygenWebSocketConnection}}(), ReentrantLock(), DefaultCleanupPolicy(), nothing)

"""
    setup_bonito_connection(
        context::Context;
        setup_all=false,
        setup_route=setup_all,
        setup_force_connection=setup_all,
        route_base="/bonito_websocket/"
    )

This is the high level function to setup bonito connection. It will register the route and create a connection if needed.

In the simplest use case you can simply pass `setup_bonito_connection(CONTEXT[]; setup_all=true)` and it will set up everything for you. Please see the guide for advanced usage.
"""
function setup_bonito_connection(
    context::Context;
    setup_all=false,
    setup_route=setup_all,
    setup_force_connection=setup_all,
    route_base="/bonito_websocket/"
)
    context.ext[:bonito_connection] = BonitoConnectionContext()
    handler = mk_bonito_websocket_handler(context)
    connection = OxygenWebSocketConnection(context, route_base)
    if setup_route
        Oxygen.Core.register(context, WEBSOCKET, route_base * "{session_id}", handler)
    end
    if setup_force_connection
        force_connection!(connection)
    end
    return (;
        connection,
        handler
    )
end


function mk_bonito_websocket_handler(context::Context)
    if !(:bonito_connection in keys(context.ext))
        error("bonito_connection not setup in context (did you call setup_bonito_connection(...)?)")
    end
    bonito_context = context.ext[:bonito_connection]
    function bonito_websocket_handler(websocket::HTTP.WebSocket, session_id::String)
        session = nothing
        lock(bonito_context.open_connections_lock) do
            session = bonito_context.open_connections[session_id]
        end
        handler = session.connection.handler

        @debug("opening ws connection for session: $(session.id)")
        run_connection_loop(session, handler, websocket)
    end
    return bonito_websocket_handler
end


function setup_connection(session::Session{OxygenWebSocketConnection})
    if !(:bonito_connection in keys(session.connection.context.ext))
        error("bonito_connection not setup in context (did you call setup_bonito_connection(...)?)")
    end
    context = session.connection.context
    bonito_context = context.ext[:bonito_connection]
    if context.service.external_url[] == nothing
        error("external_url not set in context (did you call start the server yet?)")
    end
    external_url_base = context.service.external_url[]
    session_id = session.id
    lock(bonito_context.open_connections_lock) do
        bonito_context.open_connections[session_id] = session
    end
    external_url = external_url_base * session.connection.endpoint
    return setup_websocket_connection_js(external_url, session)
end
