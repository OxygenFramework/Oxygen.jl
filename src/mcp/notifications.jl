# Notification event model, filters, broker, and change broadcasts. Split out
# of `MCP.Subscriptions` so domain modules can publish changes without depending
# on the listen-stream machinery.

module Notifications

using ...AppContext: ServerContext
using ...PubSub
using ...Streaming: StreamEvent

using ..Serialization: string_keyed

export notify_change, close_broker!

# ----------------------------------------------------------------------------
# Event model
# ----------------------------------------------------------------------------

"""
    SubscriptionNotification(method, params, uri=nothing)

A server-initiated JSON-RPC notification broadcast through the MCP broker.
`uri` is set for `notifications/resources/updated` so per-stream filters can
match without decoding `params`.
"""
struct SubscriptionNotification <: StreamEvent
    method :: String
    params :: Dict{String,Any}
    uri    :: Union{Nothing,String}
end

function SubscriptionNotification(
    method::AbstractString,
    params::AbstractDict) :: SubscriptionNotification

    return SubscriptionNotification(String(method), string_keyed(params), nothing)
end

# The broker payload is the generic engine's event type, so a listen stream's
# queue can be the broker subscription queue verbatim (no bridge task).
const MCPBroker = PubSub.Broker{StreamEvent}

# Reserved `_meta` key carrying the listen request id on every stream message.
const META_SUBSCRIPTION_ID = "io.modelcontextprotocol/subscriptionId"

# Limits: each subscription pins a record, a queue, and (on HTTP) an open
# connection for an unbounded lifetime, so the count and the id size are bounded.
const MAX_LISTEN_SUBSCRIPTIONS   = 64
const MAX_RESOURCE_SUBSCRIPTIONS = 256
const MAX_SUBSCRIPTION_ID_LENGTH = 128
const LISTEN_BACKLOG_CAP         = 256
const LEGACY_NOTIFICATION_CAP    = 1000

const LISTEN_LIMIT_MESSAGE =
    "subscriptions/listen: active subscription limit reached ($(MAX_LISTEN_SUBSCRIPTIONS))"
const LISTEN_DUPLICATE_MESSAGE =
    "subscriptions/listen id is already active on this connection"

# ----------------------------------------------------------------------------
# Filter
# ----------------------------------------------------------------------------

"""
    SubscriptionFilter(; tools_list_changed=false, prompts_list_changed=false,
                       resources_list_changed=false, resource_uris=Set{String}())

The notification types a `subscriptions/listen` stream opted into. A server
MUST NOT send notification types the client did not request, so every delivery
is checked against this filter.
"""
Base.@kwdef struct SubscriptionFilter
    tools_list_changed     :: Bool        = false
    prompts_list_changed   :: Bool        = false
    resources_list_changed :: Bool        = false
    resource_uris          :: Set{String} = Set{String}()
end

"""
    parse_subscription_filter(notifications) :: Union{SubscriptionFilter,String}

Validate and parse the `notifications` filter object of a `subscriptions/listen`
request. Returns the parsed filter, or a violation message the caller rejects
with `-32602`: the filter must be an object, the `*ListChanged` flags booleans,
`resourceSubscriptions` an array of at most `MAX_RESOURCE_SUBSCRIPTIONS`
strings, and at least one notification type must be requested. Unknown keys are
ignored for forward compatibility.
"""
function parse_subscription_filter(notifications) :: Union{SubscriptionFilter,String}
    if !(notifications isa AbstractDict)
        return "notifications must be an object"
    end

    for key in ("toolsListChanged", "promptsListChanged", "resourcesListChanged")
        if haskey(notifications, key) && !(notifications[key] isa Bool)
            return "$key must be a boolean"
        end
    end

    uris = Set{String}()
    if haskey(notifications, "resourceSubscriptions")
        subscriptions = notifications["resourceSubscriptions"]
        if !(subscriptions isa AbstractVector)
            return "resourceSubscriptions must be an array of strings"
        end
        if length(subscriptions) > MAX_RESOURCE_SUBSCRIPTIONS
            return "resourceSubscriptions exceeds the limit of $(MAX_RESOURCE_SUBSCRIPTIONS) URIs"
        end
        for uri in subscriptions
            if !(uri isa AbstractString)
                return "resourceSubscriptions must be an array of strings"
            end
            push!(uris, String(uri))
        end
    end

    filter = SubscriptionFilter(
        tools_list_changed     = get(notifications, "toolsListChanged", false) === true,
        prompts_list_changed   = get(notifications, "promptsListChanged", false) === true,
        resources_list_changed = get(notifications, "resourcesListChanged", false) === true,
        resource_uris          = uris,
    )

    if !(filter.tools_list_changed || filter.prompts_list_changed ||
         filter.resources_list_changed) && isempty(filter.resource_uris)
        return "at least one notification type must be requested"
    end
    return filter
end

"""
    filter_to_wire(filter) :: Dict

Serialize the honored filter subset to the `notifications` field of the
acknowledgement. Types not subscribed are omitted; URIs are emitted sorted (the
set has no stable order).
"""
function filter_to_wire(filter::SubscriptionFilter) :: Dict{String,Any}
    wire = Dict{String,Any}()
    if filter.tools_list_changed
        wire["toolsListChanged"] = true
    end
    if filter.prompts_list_changed
        wire["promptsListChanged"] = true
    end
    if filter.resources_list_changed
        wire["resourcesListChanged"] = true
    end
    if !isempty(filter.resource_uris)
        wire["resourceSubscriptions"] = sort!(collect(filter.resource_uris))
    end
    return wire
end

"""
    filter_wants(filter, event) :: Bool

Whether `event` was opted into by `filter`.
"""
function filter_wants(
    filter::SubscriptionFilter,
    event::SubscriptionNotification) :: Bool

    method = event.method
    if method == "notifications/tools/list_changed"
        return filter.tools_list_changed
    elseif method == "notifications/prompts/list_changed"
        return filter.prompts_list_changed
    elseif method == "notifications/resources/list_changed"
        return filter.resources_list_changed
    elseif method == "notifications/resources/updated"
        return !isnothing(event.uri) && event.uri in filter.resource_uris
    end
    return false
end

# Whether the server currently advertises the `listChanged` capability for a
# kind. Kept as a function (not a constant) because the registries are mutable.
function list_changed_capable(ctx::ServerContext, kind::Symbol) :: Bool
    if kind === :tools
        return true
    elseif kind === :prompts
        return !isempty(ctx.mcp.prompts)
    elseif kind === :resources
        return has_resources(ctx)
    end
    return false
end

has_resources(ctx::ServerContext) :: Bool = !isempty(ctx.mcp.resources) || !isempty(ctx.mcp.resource_templates)

"""
    honored_filter(ctx, requested) :: SubscriptionFilter

Mask a requested filter by the capabilities this server advertises: types it
cannot deliver are omitted from the acknowledgement, so the ack is the honest
source of what will actually be sent.
"""
function honored_filter(ctx::ServerContext, requested::SubscriptionFilter)::SubscriptionFilter
    resources = has_resources(ctx)
    return SubscriptionFilter(
        tools_list_changed     = requested.tools_list_changed && list_changed_capable(ctx, :tools),
        prompts_list_changed   = requested.prompts_list_changed && list_changed_capable(ctx, :prompts),
        resources_list_changed = requested.resources_list_changed && list_changed_capable(ctx, :resources),
        resource_uris          = resources ? requested.resource_uris : Set{String}(),
    )
end

# ----------------------------------------------------------------------------
# Broker
# ----------------------------------------------------------------------------

"""
    broker(ctx) :: MCPBroker

The context's notification broker, created lazily (the `MCPContext` is built
before this module is defined, so the field is an untyped `Ref`). A broker that
has been closed is retired: the accessor never hands one out, so a fresh broker
is built on the next call. The `isopen` check is lock-free, which keeps it safe
under `subscriptions_lock` (acquiring `broker.lock` there would violate this
file's lock ordering).
"""
function broker(ctx::ServerContext) :: MCPBroker
    existing = ctx.mcp.broker[]
    if existing isa MCPBroker && isopen(existing)
        return existing
    end

    return lock(ctx.mcp.subscriptions_lock) do
        existing = ctx.mcp.broker[]
        if existing isa MCPBroker && isopen(existing)
            return existing
        end
        created = MCPBroker(; cap=MAX_LISTEN_SUBSCRIPTIONS)
        ctx.mcp.broker[] = created
        return created
    end
end

"""
    close_broker!(ctx)

Close the context's notification broker (ending any remaining subscriptions and
waking their consumers) and detach it, so the next `broker(ctx)` builds a
fresh, open broker. Called during `terminate`, after listens and sessions have
been shut down; a context that never created a broker is left untouched.
"""
function close_broker!(ctx::ServerContext)
    mcp_broker = lock(ctx.mcp.subscriptions_lock) do
        existing = ctx.mcp.broker[]
        ctx.mcp.broker[] = nothing
        return existing
    end
    if mcp_broker isa MCPBroker
        # `close` takes `broker.lock`, which must not be acquired while
        # holding `subscriptions_lock`.
        close(mcp_broker)
    end
    return nothing
end


# ----------------------------------------------------------------------------
# Broadcast / notify_change
# ----------------------------------------------------------------------------

"""
    broadcast_notification(ctx, event) :: Int

Publish a server notification to every matching subscriber (listen streams and
the legacy sinks). Returns the number of queues it was enqueued into.
"""
function broadcast_notification(ctx::ServerContext, event::SubscriptionNotification) :: Int
    return PubSub.publish!(broker(ctx), event.method, event)
end

"""
    notify_change(ctx, kind, value=nothing) :: Int

Publish a server-initiated change notification to every matching subscriber.
`kind` selects the notification:

  * `notify_change(ctx, :resource_updated, uri)`: the contents of `uri` changed
    (`notifications/resources/updated`);
  * `notify_change(ctx, :tools_changed)`, `notify_change(ctx, :prompts_changed)`,
    `notify_change(ctx, :resources_changed)`: the corresponding list changed
    (`notifications/{tools,prompts,resources}/list_changed`).

Returns the number of subscriber queues the notification was enqueued into; a
queue that dropped the value (`:drop_newest`) or was disconnected does not
count.
"""
function notify_change(ctx::ServerContext, kind::Symbol, value=nothing) :: Int
    if kind === :resource_updated
        if !(value isa AbstractString)
            throw(ArgumentError("notify_change: :resource_updated requires a resource uri"))
        end
        uri = String(value)
        return broadcast_notification(ctx, SubscriptionNotification(
            "notifications/resources/updated", Dict{String,Any}("uri" => uri), uri))
    end

    if kind in (:tools_changed, :prompts_changed, :resources_changed)
        if !isnothing(value)
            throw(ArgumentError("notify_change: :$kind does not take a value"))
        end
        component = if kind === :tools_changed
            "tools"
        elseif kind === :prompts_changed
            "prompts"
        else
            "resources"
        end
        return broadcast_notification(ctx, SubscriptionNotification(
            "notifications/$(component)/list_changed", Dict{String,Any}(), nothing))
    end

    throw(ArgumentError("notify_change: kind must be :resource_updated, " *
                        ":tools_changed, :prompts_changed, or :resources_changed"))
end

end # module Notifications
