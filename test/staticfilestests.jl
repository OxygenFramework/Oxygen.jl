module StaticFilesTests
using Test
using HTTP
using ..Constants
using Oxygen; @oxidize

staticfiles("content", "static")

serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

@testset "staticfiles page can be hit more than once" begin
    expected = read("content/test.txt", String)

    r = HTTP.get("$localhost/static/test.txt")
    @test r.status == 200
    @test String(r.body) == expected

    # a second request to the same mounted file must return the same content
    r = HTTP.get("$localhost/static/test.txt")
    @test r.status == 200
    @test String(r.body) == expected
end

terminate()
println()

end
