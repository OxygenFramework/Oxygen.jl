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
const SESSION_TOUCH_SECONDS = 60.0
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
    ids = String[]
    for (id, value) in ctx.mcp.sessions
        if !(value isa MCPSession)
            continue
        end
        if value.last_seen >= cutoff
            continue
        end
        push!(ids, id)
        push!(expired, value)
    end
    # Delete after the walk: only the expired ids are collected (the previous
    # implementation copied the whole session table on every sweep).
    for id in ids
        delete!(ctx.mcp.sessions, id)
    end
    return expired
end

# Drop the least-recently-seen session, returning it for teardown. Callers hold
# `sessions_lock`.
function evict_oldest!(ctx::ServerContext)::Union{Nothing,MCPSession}
    oldest = nothing
    for value in values(ctx.mcp.sessions)
        if !(value isa MCPSession)
            continue
        end
        if isnothing(oldest) || value.last_seen < oldest.last_seen
            oldest = value
        end
    end
    if !isnothing(oldest)
        delete!(ctx.mcp.sessions, oldest.id)
    end
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
        if session isa MCPSession
            terminate_session!(ctx, session)
        end
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
            if isnothing(victim)
                break
            end
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
        if !(session isa MCPSession)
            return nothing
        end
        if session.closed
            return nothing
        end
        # Refresh the idle clock at most once a minute: the TTL is an hour, and
        # writing every request keeps the lock's cache line hot under load.
        now = time()
        if now - session.last_seen >= SESSION_TOUCH_SECONDS
            session.last_seen = now
        end
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
    if isnothing(value)
        return nothing
    end
    if value === :invalid
        return :invalid
    end
    session = find_session(ctx, String(value))
    return isnothing(session) ? :unknown : session
end

"""
    resolve_session_or_error(ctx, req) :: Union{Nothing,MCPSession,Tuple{Int,Dict}}

Resolve the `Mcp-Session-Id` header, translating a malformed or unknown id into
the `(status, body)` HTTP error every transport responds with. Returns the live
`MCPSession`, `nothing` for the anonymous case, or that error tuple.
"""
function resolve_session_or_error(ctx::ServerContext, req::HTTP.Request)
    resolved = resolve_session(ctx, req)
    if resolved === :invalid
        return (400, error_body(nothing, MCP_INVALID_REQUEST,
                                "Invalid Mcp-Session-Id header"))
    end
    if resolved === :unknown
        return (404, error_body(nothing, MCP_INVALID_REQUEST,
                                "Unknown or expired session"))
    end
    return resolved
end

# --- Accessors shared by dispatch and the notification filters --------------

# The anonymous (header-less) transport keeps its state on `MCPContext`; a real
# session keeps the same fields on `MCPSession`. These accessors read or write
# whichever is in effect, so callers do not repeat the ternary.

legacy_version(ctx::ServerContext, session::Union{Nothing,MCPSession})::String =
    isnothing(session) ? ctx.mcp.session_version[] : session.version

function mark_initialized!(ctx::ServerContext, session::Union{Nothing,MCPSession})
    if isnothing(session)
        ctx.mcp.initialized[] = true
    else
        lock(session.lock) do
            session.initialized = true
        end
    end
    return nothing
end

# Record a negotiated `initialize` handshake: the version plus the flag that
# arms legacy server→client delivery.
function set_handshake!(ctx::ServerContext, session::Union{Nothing,MCPSession}, version::String)
    if isnothing(session)
        ctx.mcp.session_version[] = version
        ctx.mcp.handshake_complete[] = true
    else
        lock(session.lock) do
            session.version = version
            session.handshake_complete = true
        end
    end
    return nothing
end

# Whether the client completed an `initialize` handshake (see
# `legacy_event_wanted` for why `notifications/initialized` alone is not proof).
function handshake_ready(ctx::ServerContext, session::Union{Nothing,MCPSession})::Bool
    if isnothing(session)
        return ctx.mcp.initialized[] && ctx.mcp.handshake_complete[]
    end
    return lock(session.lock) do
        session.initialized && session.handshake_complete
    end
end

# Legacy `resources/subscribe` membership for the anonymous state or a session.
function legacy_subscribed(ctx::ServerContext, session::Union{Nothing,MCPSession},
                           uri::String)::Bool
    if isnothing(session)
        return lock(ctx.mcp.subscriptions_lock) do
            uri in ctx.mcp.legacy_subscriptions
        end
    end
    return lock(session.lock) do
        uri in session.subscriptions
    end
end

function set_legacy_subscribed(ctx::ServerContext, session::Union{Nothing,MCPSession},
                               uri::String; subscribed::Bool)
    if isnothing(session)
        lock(ctx.mcp.subscriptions_lock) do
            subscribed ? push!(ctx.mcp.legacy_subscriptions, uri) :
                         delete!(ctx.mcp.legacy_subscriptions, uri)
        end
    else
        lock(session.lock) do
            subscribed ? push!(session.subscriptions, uri) :
                         delete!(session.subscriptions, uri)
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
        if session.closed
            return false
        end
        push!(session.sinks, sub)
        return true
    end
    if !accepted
        PubSub.unsubscribe!(broker(ctx), sub)
    end
    return accepted
end

function remove_sink!(session::MCPSession, sub::PubSub.Subscription)
    lock(session.lock) do
        filter!(candidate -> candidate !== sub, session.sinks)
    end
    return nothing
end
