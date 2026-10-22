module MCPTestRunner

using Test
using HTTP
using JSON
using Oxygen

include("constants.jl"); using .Constants
include("test_utils.jl"); using .TestUtils
include("mcptests.jl")
include("mcp_streamtests.jl")
include("mcp_router_tests.jl")
include("mcp_resourcetests.jl")
include("mcp_spec_tests.jl")
include("mcp_transport_utils_tests.jl")
include("mcp_exports_tests.jl")
include("mcp_subscriptiontests.jl")

end
