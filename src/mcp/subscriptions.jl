# Modern listen streams, legacy resource subscriptions, and their method
# routing. The event model, filters, and broker live in `MCP.Notifications`;
# this module owns the transport-facing stream lifecycle.

module Subscriptions

using HTTP

using ...AppContext: ServerContext
using ...PubSub
using ...Streaming: StreamEvent, FinalEvent, ErrorEvent, EventStream, cancel_stream!

using ..Envelopes: META_KEY
using ..Errors: error_body, MCP_INTERNAL_ERROR, MCP_INVALID_PARAMS, MCP_INVALID_REQUEST
using ..Notifications: SubscriptionFilter, SubscriptionNotification,
    META_SUBSCRIPTION_ID, MAX_LISTEN_SUBSCRIPTIONS,
    MAX_SUBSCRIPTION_ID_LENGTH, LISTEN_BACKLOG_CAP, LEGACY_NOTIFICATION_CAP,
    LISTEN_LIMIT_MESSAGE, LISTEN_DUPLICATE_MESSAGE,
    parse_subscription_filter, filter_to_wire, filter_wants,
    list_changed_capable, honored_filter, broker
using ..Sessions: MCPSession, handshake_ready, legacy_subscribed, set_legacy_subscribed, add_sink!
using ..Serialization: result_body, result_response, string_keyed
using ..Specs: LATEST_MODERN_SPEC, result_envelope
using ..Streams: notification

import ..Dispatch: handle_method

export close_listens!

include("subscriptions/listen.jl")
include("subscriptions/legacy.jl")
include("subscriptions/methods.jl")

end # module Subscriptions
