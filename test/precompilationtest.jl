module PrecompilationTests

using Test
using HTTP
using Oxygen: text 
using ..Constants

# Load in the custom pacakge & trigger any precompilation
push!(LOAD_PATH, "./TestPackage")
using TestPackage

# call the start function from the TestPackage
start(;async=true, host=HOST, port=PORT, show_banner=false, access_log=nothing)

@testset "TestPackage" begin

    r = HTTP.get("$localhost")
    @test r.status == 200
    @test text(r) == "hello world"

    r = HTTP.get("$localhost/add?a=5&b=10")
    @test r.status == 200
    @test text(r) == "15"

    # test default value which should be 3
    r = HTTP.get("$localhost/add?a=3")
    @test r.status == 200
    @test text(r) == "6"


    r = HTTP.get("$localhost/add/extractor?a=5&b=10")
    @test r.status == 200
    @test text(r) == "15"

    # test default value which should be 3
    r = HTTP.get("$localhost/add/extractor?a=3")
    @test r.status == 200
    @test text(r) == "6"

end

# Call the stop() function from the TestPackage
stop()

end