# Streamable HTTP and stdio entry points. This is the top of the dependency
# graph: it consumes JSON-RPC, dispatch, sessions, streams, subscriptions, and
# notifications, and nothing below it imports `MCP.Transports`.

module Transports

using HTTP
using JSON

using ...AppContext: ServerContext
using ...PubSub
using ...Streaming: EventStream, FinalEvent, ErrorEvent, pump_stream,
    drain_stream!, cancel_stream!, stream_sse

using ..Dispatch: transport_spec
using ..Errors: error_body, MCP_PARSE_ERROR, MCP_INVALID_REQUEST, MCP_INTERNAL_ERROR
using ..Headers: header_name_equals
using ..JSONRPC: process, process_batch
using ..Notifications: broker, SubscriptionNotification
using ..Sessions: MCPSession, SESSION_HEADER, new_session!, resolve_session_or_error,
    terminate_session!, mirror_anonymous!, legacy_version, remove_sink!
using ..Specs: SUPPORTED_VERSIONS, uses_sessions, get_policy, delete_policy
using ..Streams: StreamedCall, streamed_body, streamed_frame, notification
using ..Subscriptions: ListenCall, listen_frame, remove_listen!, subscribe_legacy!,
    close_listens!

export handle, handle_get, handle_delete, stdio_loop

include("transports/accept.jl")
include("transports/io.jl")
include("transports/sse.jl")
include("transports/transport.jl")
include("transports/stdio.jl")

end # module Transports
