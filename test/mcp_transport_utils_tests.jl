module MCPTransportUtilsTests

using Test
using HTTP
using Oxygen

const MCP = Oxygen.Core.MCP

@testset "Accept header collection" begin
    req = HTTP.Request("POST", "/",
                       ["Accept" => "application/json", "accept" => "text/event-stream"])
    @test MCP.Transports.accept_headers(req) == ["application/json,text/event-stream"]
    @test MCP.Transports.accept_headers(HTTP.Request("POST", "/")) == String[]
end

@testset "Accept media-range parsing" begin
    @test MCP.Transports.parse_media_range("text/event-stream") == ("text/event-stream", 1.0)
    @test MCP.Transports.parse_media_range("TEXT/EVENT-STREAM; Q=0.5") == ("text/event-stream", 0.5)
    @test MCP.Transports.parse_media_range(" text/event-stream ; q=oops ") == ("text/event-stream", 0.0)
    @test MCP.Transports.parse_media_range("application/json; charset=utf-8") == ("application/json", 1.0)
end

@testset "event-stream negotiation" begin
    accept(header) = HTTP.Request("POST", "/", ["Accept" => header])

    @test MCP.Transports.accepts_event_stream(accept("text/event-stream"))
    @test MCP.Transports.accepts_event_stream(accept("TEXT/EVENT-STREAM"))
    @test MCP.Transports.accepts_event_stream(accept("text/event-stream;q=0.5"))
    @test MCP.Transports.accepts_event_stream(accept("text/*"))
    @test MCP.Transports.accepts_event_stream(accept("*/*"))
    @test !MCP.Transports.accepts_event_stream(accept("text/event-stream;q=0"))
    @test !MCP.Transports.accepts_event_stream(accept("application/json"))
    @test !MCP.Transports.accepts_event_stream(HTTP.Request("POST", "/"))

    # GET uses the explicit form: wildcards must not hold the connection open.
    @test MCP.Transports.accepts_event_stream(accept("text/event-stream"); explicit=true)
    @test MCP.Transports.accepts_event_stream(accept("TEXT/EVENT-STREAM"); explicit=true)
    @test !MCP.Transports.accepts_event_stream(accept("text/event-stream;q=0"); explicit=true)
    @test !MCP.Transports.accepts_event_stream(accept("text/*"); explicit=true)
    @test !MCP.Transports.accepts_event_stream(accept("*/*"); explicit=true)
end

@testset "MCP entry points remain defined" begin
    for name in (:handle, :handle_get, :handle_delete, :stdio_loop)
        @test isdefined(MCP, name)
    end
    for (owner, names) in (
        (MCP.JSONRPC, (:process, :process_batch)),
        (MCP.Dispatch, (:dispatch, :request_spec, :transport_spec)),
        (MCP.Transports, (:write_json_response, :write_stream_response,
                          :stream_call, :stream_listen_call, :stream_notifications)),
    )
        for name in names
            @test isdefined(owner, name)
        end
    end
end

end
