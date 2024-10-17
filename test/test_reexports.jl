module TestReexports
using Test
import HTTP
import Oxygen

@testset "Testing HTTP Reexports" begin
    @test Oxygen.Request        == HTTP.Request
    @test Oxygen.Response       == HTTP.Response
    @test Oxygen.Stream         == HTTP.Stream
    @test Oxygen.WebSocket      == HTTP.WebSocket
    @test Oxygen.queryparams    == HTTP.queryparams
end

end