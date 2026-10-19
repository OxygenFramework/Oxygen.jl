module MCP

using Reexport

using ..Types
using ..AppContext: ServerContext, MCPContext
using ..PubSub
using ..Util: response_bytes
using ..Streaming: StreamEvent, FinalEvent, ErrorEvent, StreamCancelled,
    EventStream, enqueue!, start_stream!, pump_stream, drain_stream!,
    cancel_stream!, adopt_channel,
    STREAM_BUFFER_SIZE, stream_sse, normalize_event

include("mcp/errors.jl");        @reexport using .Errors
include("mcp/envelopes.jl");     @reexport using .Envelopes
include("mcp/headers.jl");       @reexport using .Headers
include("mcp/specs.jl");         @reexport using .Specs
include("mcp/sessions.jl");      @reexport using .Sessions
include("mcp/serialization.jl"); @reexport using .Serialization
include("mcp/streams.jl");       @reexport using .Streams
include("mcp/notifications.jl"); @reexport using .Notifications
include("mcp/dispatch.jl");      @reexport using .Dispatch
include("mcp/discovery.jl");     @reexport using .Discovery
include("mcp/tools.jl");         @reexport using .Tools
include("mcp/prompts.jl");       @reexport using .Prompts
include("mcp/resources.jl");     @reexport using .Resources
include("mcp/subscriptions.jl"); @reexport using .Subscriptions
include("mcp/jsonrpc.jl");       @reexport using .JSONRPC
include("mcp/transports.jl");    @reexport using .Transports

end
