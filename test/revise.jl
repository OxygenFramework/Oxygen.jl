module ReviseTest

using Test
using Oxygen; @oxidise
using ..Constants
using HTTP

@get "/" function()
    return text("Ok")
end

# Test error message when Revise not used

error_task = @async begin
    for revise in (:lazy, :eager)
        @test_throws "You must load Revise.jl before Oxygen.jl" serve(port=PORT, host=HOST, show_errors=false, show_banner=false, access_log=nothing, revise=revise)
    end
end

if timedwait(()->istaskdone(error_task), 60) == :timed_out
    error("Timed out waiting for Revise usage error")
end

# Test usage with user provided middleware

@eval Main module Revise
    #=
    Need to support the following in this mock:

    Revise = Main.Revise
    isempty(Revise.revision_queue)
    wait(Revise.revision_event)
    Revise.revise()
    =#

    revision_queue = [nothing] # non-empty
    revision_event = Base.Event()
    notify(revision_event) # wait(...) always returns immediately
    revise_called_count = 0

    function revise()
        global revise_called_count
        revise_called_count += 1
    end
end

invocation = []

function handler1(handler)
    return function(req::HTTP.Request)
        push!(invocation, 1)
        handler(req)
    end
end

Oxygen.WAS_LOADED_AFTER_REVISE[] = true
serve(port=PORT, host=HOST, show_errors=false, show_banner=false, access_log=nothing, revise=:lazy, middleware=[handler1], async=true)
@test String(HTTP.get("$localhost/").body) == "Ok"
@test invocation == [1]
@test Main.Revise.revise_called_count == 1
# Caveat: We have put the Revise mock in Main, but now can't delete it.
# Hopefully this doesn't affect any other tests.
Oxygen.WAS_LOADED_AFTER_REVISE[] = false

terminate()
println()

end

