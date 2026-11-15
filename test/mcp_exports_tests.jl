module MCPExportsTests

using Test
using Oxygen

@testset "MCP public exports" begin
    for name in (
        Symbol("@tool"), :tool,
        Symbol("@prompt"), :prompt,
        Symbol("@resource"), :resource, :resource_folder,
        :mcp_stream, :emit, :progress, :result, :check_cancelled,
        :notify_change,
    )
        @test isdefined(Oxygen, name)
    end
end

end
