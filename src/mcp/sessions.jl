# HTTP session management for the legacy (initialize-handshake) era.
# Included into the `MCP` module by `../mcp.jl`, before `subscriptions.jl`.
#
# The modern revision is stateless and never resolves a session. Legacy clients
# that want isolation from other clients echo the `Mcp-Session-Id` returned by
# `initialize`; requests without the header fall back to the context-wide
# anonymous state (the original single-session behavior). A header naming an
# unknown or expired session is rejected with HTTP 404, as the transport
# requires.

const SESSION_HEADER = "Mcp-Session-Id"
const SESSION_TTL_SECONDS = 3600.0
const MAX_SESSIONS = 1024

"""
    MCPSession

Per-client state for the legacy era over Streamable HTTP: the negotiated
protocol version, handshake flags, and the `resources/subscribe` set. The
anonymous (header-less) transport keeps using the context-wide equivalents on
`MCPContext`, so pre-session clients behave exactly as before.
"""
mutable struct MCPSession
    id                 :: String
    version            :: String
    initialized        :: Bool
    handshake_complete :: Bool
    subscriptions      :: Set{String}
    sinks              :: Vector{PubSub.Subscription}
    closed             :: Bool
    last_seen          :: Float64
    lock               :: ReentrantLock
end

MCPSession(id::AbstractString) = MCPSession(
    String(id), LATEST_LEGACY, false, false, Set{String}(),
    PubSub.Subscription[], false, time(), ReentrantLock())

# Remove sessions idle past the TTL. Callers hold `sessions_lock`; the return
# value lets them run the (broker-touching) teardown after releasing it.
function sweep_sessions!(ctx::ServerContext)::Vector{MCPSession}
    cutoff = time() - SESSION_TTL_SECONDS
    expired = MCPSession[]
    for (id, value) in collect(ctx.mcp.sessions)
        value isa MCPSession || continue
        value.last_seen < cutoff || continue
        delete!(ctx.mcp.sessions, id)
        push!(expired, value)
    end
    return expired
end

# Drop the least-recently-seen session, returning it for teardown. Callers hold
# `sessions_lock`.
function evict_oldest!(ctx::ServerContext)::Union{Nothing,MCPSession}
    oldest = nothing
    for value in values(ctx.mcp.sessions)
        value isa MCPSession || continue
        (oldest === nothing || value.last_seen < oldest.last_seen) && (oldest = value)
    end
    oldest === nothing || delete!(ctx.mcp.sessions, oldest.id)
    return oldest
end

# End a session's live notification sinks and mark it unusable. The broker is
# only touched after `session.lock` is released: predicates run under the broker
# lock and take session locks, never the other way around.
function terminate_session!(ctx::ServerContext, session::MCPSession)
    lock(session.lock) do
        session.closed = true
    end

    broker = ctx.mcp.broker[]
    sinks = lock(session.lock) do
        found = copy(session.sinks)
        empty!(session.sinks)
        found
    end

    for sub in sinks
        try
            broker isa MCPBroker ? PubSub.unsubscribe!(broker, sub) : close(sub)
        catch
        end
    end
    return nothing
end

"""
    close_sessions!(ctx)

Terminate every session (unsubscribing its notification sinks) and empty the
registry. Called during `terminate`.
"""
function close_sessions!(ctx::ServerContext)
    sessions = lock(ctx.mcp.sessions_lock) do
        found = collect(values(ctx.mcp.sessions))
        empty!(ctx.mcp.sessions)
        found
    end
    for session in sessions
        session isa MCPSession && terminate_session!(ctx, session)
    end
    return nothing
end

"""
    new_session!(ctx) :: MCPSession

Create a session, sweeping expired ones and evicting the oldest at capacity.
"""
function new_session!(ctx::ServerContext)::MCPSession
    evicted = MCPSession[]
    session = MCPSession(string(UUIDs.uuid4()))
    lock(ctx.mcp.sessions_lock) do
        append!(evicted, sweep_sessions!(ctx))
        while length(ctx.mcp.sessions) >= MAX_SESSIONS
            victim = evict_oldest!(ctx)
            victim === nothing && break
            push!(evicted, victim)
        end
        ctx.mcp.sessions[session.id] = session
    end
    for victim in evicted
        terminate_session!(ctx, victim)
    end
    return session
end

"""
    find_session(ctx, id) :: Union{Nothing,MCPSession}

Look up a live session and touch its `last_seen` timestamp.
"""
function find_session(ctx::ServerContext, id::AbstractString)::Union{Nothing,MCPSession}
    return lock(ctx.mcp.sessions_lock) do
        session = get(ctx.mcp.sessions, String(id), nothing)
        session isa MCPSession || return nothing
        session.closed && return nothing
        session.last_seen = time()
        return session
    end
end

"""
    resolve_session(ctx, req) :: Union{Nothing,MCPSession,Symbol}

Resolve the `Mcp-Session-Id` header of an HTTP request. Returns `nothing` when
the header is absent (the anonymous session), the `MCPSession` for a live one,
`:invalid` for a duplicated or unsafe header, or `:unknown` for an id this
server does not know.
"""
function resolve_session(ctx::ServerContext, req::HTTP.Request)
    value = mcp_standard_header(req, SESSION_HEADER)
    value === nothing && return nothing
    value === :invalid && return :invalid
    session = find_session(ctx, String(value))
    return session === nothing ? :unknown : session
end

# --- Accessors shared by dispatch and the notification filters --------------

legacy_version(ctx::ServerContext, session::Union{Nothing,MCPSession})::String =
    session === nothing ? ctx.mcp.session_version[] : session.version

function mark_initialized!(ctx::ServerContext, session::Union{Nothing,MCPSession})
    if session === nothing
        ctx.mcp.initialized[] = true
    else
        lock(session.lock) do
            session.initialized = true
        end
    end
    return nothing
end

# Header-less HTTP `initialize` keeps the legacy global flags in sync so curl
# users (and tests) that never echo the session id behave exactly as before; a
# client that echoes the id is fully isolated.
function mirror_anonymous!(ctx::ServerContext, session::MCPSession)
    lock(session.lock) do
        ctx.mcp.session_version[] = session.version
        ctx.mcp.initialized[] = session.initialized
        ctx.mcp.handshake_complete[] = session.handshake_complete
    end
    return nothing
end

# Register a legacy notification sink on a session, rejecting it when the
# session was terminated between resolution and registration.
function add_sink!(ctx::ServerContext, session::MCPSession, sub::PubSub.Subscription)::Bool
    accepted = lock(session.lock) do
        session.closed && return false
        push!(session.sinks, sub)
        return true
    end
    accepted || PubSub.unsubscribe!(broker(ctx), sub)
    return accepted
end

function remove_sink!(session::MCPSession, sub::PubSub.Subscription)
    lock(session.lock) do
        filter!(candidate -> candidate !== sub, session.sinks)
    end
    return nothing
end
