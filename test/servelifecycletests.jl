module ServeLifecycleTests

using Test
using HTTP
using Oxygen; @oxidize
using ..Constants

# Dedicated ports so this suite cannot collide with its neighbors.
const FIRST_PORT = PORT + 7
const SECOND_PORT = PORT + 8

function wait_for_server(url; timeout=30)
    deadline = time() + timeout
    while time() < deadline
        try
            HTTP.get(url; retry=false, status_exception=false)
            return true
        catch
            sleep(0.05)
        end
    end
    return false
end

@testset "a stopped serve() cannot stop the server that replaced it" begin
    # A blocking serve() in a task waits on the server it started.
    first_task = @async serve(port=FIRST_PORT, host=HOST, async=false,
                              show_banner=false, docs=false, metrics=false, mcp=false)
    @test wait_for_server("http://$HOST:$FIRST_PORT/")
    first_server = CONTEXT[].service.server[]

    # Stop the first server; the blocked serve() task will notice and unwind.
    terminate()

    # Replace it immediately with a second server on the same context.
    second_server = serve(port=SECOND_PORT, host=HOST, async=true,
                          show_banner=false, docs=false, metrics=false, mcp=false)
    @test CONTEXT[].service.server[] === second_server

    # The unwinding serve() call must return the server it started and must
    # not tear the replacement down on its way out. Pre-fix, the call waited
    # on the replacement instead (so it had to be stopped to let the task
    # finish) and its cleanup then stopped the replacement too.
    if timedwait(() -> istaskdone(first_task), 2.0) == :timed_out
        terminate()
    end
    @test fetch(first_task) === first_server
    @test CONTEXT[].service.server[] === second_server
    @test isopen(CONTEXT[].service)
    @test getexternalurl() == "http://$HOST:$SECOND_PORT"

    terminate()
    wait(first_task)
end

terminate()

end
