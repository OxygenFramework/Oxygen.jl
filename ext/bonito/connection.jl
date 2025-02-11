using HTTP.WebSockets: WebSocket, WebSocketError
using HTTP.WebSockets: receive, isclosed
using HTTP.WebSockets

using Oxygen: Oxygen
using Bonito: Bonito
using Bonito: FrontendConnection, WebSocketHandler, Session, setup_websocket_connection_js
using Bonito: run_connection_loop, register_connection!
using Bonito: CleanupPolicy, DefaultCleanupPolicy, allow_soft_close, soft_close, should_cleanup

mutable struct OxygenWebSocketConnection <: FrontendConnection
    context::Oxygen.ServerContext
    endpoint::String
    session::Union{Nothing,Session}
    handler::WebSocketHandler
end

function OxygenWebSocketConnection(context::Oxygen.ServerContext, endpoint::String)
    return OxygenWebSocketConnection(context, endpoint, nothing, WebSocketHandler())
end

Base.isopen(ws::OxygenWebSocketConnection) = isopen(ws.handler)
Base.write(ws::OxygenWebSocketConnection, binary) = write(ws.handler, binary)
Base.close(ws::OxygenWebSocketConnection) = close(ws.handler)

mutable struct BonitoConnectionContext
    cleanup_policy::CleanupPolicy
    open_connections::Dict{String, OxygenWebSocketConnection}
    cleanup_task::Union{Task, Nothing}
    lock::ReentrantLock
end

BonitoConnectionContext(policy=DefaultCleanupPolicy()) = BonitoConnectionContext(policy, Dict{String, Session{OxygenWebSocketConnection}}(), nothing, ReentrantLock())

"""
    setup_bonito_connection(
        context::Context;
        setup_all=false,
        setup_route=setup_all,
        setup_register_connection=setup_all,
        route_base="/bonito_websocket/"
    )

This is the high level function to setup bonito connection. It will register the route and create a connection if needed.

In the simplest use case you can simply pass `setup_bonito_connection(CONTEXT[]; setup_all=true)` and it will set up everything for you. Please see the guide for advanced usage.
"""
function Oxygen.setup_bonito_connection(
    context::Oxygen.ServerContext;
    setup_all=false,
    setup_route=setup_all,
    setup_register_connection=setup_all,
    route_base="/bonito-websocket/"
)
    Oxygen.BONITO_OFFLINE[] = false
    Oxygen.install_ext_context(
        context,
        bonito_connection = BonitoConnectionContext()
    )
    handler = Oxygen.mk_bonito_websocket_handler(context)
    if setup_route
        Oxygen.Core.register(context, Oxygen.WEBSOCKET, route_base * "{session_id}", handler)
    end
    function mk_connection()
        return OxygenWebSocketConnection(context, route_base)
    end
    if setup_register_connection
        register_connection!(mk_connection, OxygenWebSocketConnection)
    end
    return (;
        mk_connection,
        handler
    )
end


function Oxygen.mk_bonito_websocket_handler(context::Oxygen.ServerContext)
    if !(haskey(context.ext_context[], :bonito_connection))
        error("bonito_connection not setup in context (did you call setup_bonito_connection(...)?)")
    end
    bonito_context = context.ext_context[].bonito_connection
    function bonito_websocket_handler(websocket::HTTP.WebSocket, session_id::String)
        local connection
        lock(bonito_context.lock) do
            connection = bonito_context.open_connections[session_id]
        end
        session = connection.session
        handler = connection.handler

        @debug("opening ws connection for session: $(session.id)")
        try
            run_connection_loop(session, handler, websocket)
        finally
            if allow_soft_close(bonito_context.cleanup_policy)
                @debug("Soft closing: $(session.id)")
                soft_close(session)
            else
                @debug("Closing: $(session.id)")
                # might as well close it immediately
                close(session)
                lock(bonito_context.lock) do
                    delete!(bonito_context.open_connections, session.id)
                end
            end
        end
    end
    return bonito_websocket_handler
end

function cleanup_bonito_context(bonito_context)
    remove = Set{OxygenWebSocketConnection}()
    lock(bonito_context.lock) do
        for (session_id, connection) in bonito_context.open_connections
            if should_cleanup(bonito_context.cleanup_policy, connection.session)
                push!(remove, connection)
            end
        end
        for connection in remove
            if !isnothing(connection.session)
                session = connection.session
                delete!(bonito_context.open_connections, session.id)
                close(session)
            end
        end
    end
end

function cleanup_loop(bonito_context)
    while true
        try
            sleep(1)
            cleanup_bonito_context(bonito_context)
        catch e
            if !(e isa EOFError)
                @warn "error while cleaning up server" exception=(e, Base.catch_backtrace())
            end
        end
    end
end

function Bonito.setup_connection(session::Session, connection::OxygenWebSocketConnection)
    connection.session = session
    context = connection.context
    if !(:bonito_connection in keys(context.ext_context[]))
        error("bonito_connection not setup in context (did you call setup_bonito_connection(...)?)")
    end
    bonito_context = context.ext_context[].bonito_connection
    if context.service.external_url[] === nothing
        error("external_url not set in context (did you call start the server yet?)")
    end
    external_url_base = context.service.external_url[]
    lock(bonito_context.lock) do
        if bonito_context.cleanup_task === nothing
            bonito_context.cleanup_task = Threads.@spawn cleanup_loop(bonito_context)
        end
        bonito_context.open_connections[session.id] = connection
    end
    external_url = external_url_base * session.connection.endpoint
    return setup_websocket_connection_js(external_url, session)
end

function Bonito.setup_connection(session::Session{OxygenWebSocketConnection})
    return Bonito.setup_connection(session, session.connection)
end
