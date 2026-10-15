module ReviseTest

using Test
using Oxygen; @oxidize
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

# Eager revision: the service runs revisions while the server is up, and a
# blocking serve closes it on the way out.

Oxygen.WAS_LOADED_AFTER_REVISE[] = true
revisions_before = Main.Revise.revise_called_count

# a dedicated port: the lazy server just released PORT and its pooled
# connections may keep it in TIME_WAIT
const EAGER_PORT = PORT + 6
const EAGER_URL = "http://$HOST:$EAGER_PORT"

serve_task = @async serve(port=EAGER_PORT, host=HOST, show_errors=false, show_banner=false,
                          access_log=nothing, revise=:eager, middleware=[handler1], async=false)

# wait for the server to come up
deadline = time() + 30
while time() < deadline
    try
        HTTP.get("$EAGER_URL/"; retry=false, status_exception=false)
        break
    catch
        sleep(0.05)
    end
end

@test String(HTTP.get("$EAGER_URL/").body) == "Ok"
@test Main.Revise.revise_called_count > revisions_before
@test !isnothing(CONTEXT[].service.eager_revise[])

terminate()
wait(serve_task)

# the blocking serve shut the eager service down on its way out
@test CONTEXT[].service.eager_revise[].done[] == true
CONTEXT[].service.eager_revise[] = nothing
Oxygen.WAS_LOADED_AFTER_REVISE[] = false

terminate()
println()

end

