module LifecycleMiddlewareTests

using Test
using Suppressor
using Oxygen.Core
using Oxygen; @oxidize

@testset "LifecycleMiddleware - startup/shutdown hooks" begin
    sflag = Ref(false)
    dflag = Ref(false)

    lf = LifecycleMiddleware(
        middleware = (req->req),
        on_startup  = () -> (sflag[] = true),
        on_shutdown = () -> (dflag[] = true)
    )

    @testset "startup sets on_startup flag" begin
        startup(lf)
        @test sflag[] == true
    end

    @testset "shutdown sets on_shutdown flag" begin
        shutdown(lf)
        @test dflag[] == true
    end
end

@testset "LifecycleMiddleware - error handling case" begin
    sflag2 = Ref(false)
    dflag2 = Ref(false)

    lf2 = LifecycleMiddleware(
        middleware = (req->req),
        on_startup  = () -> begin error("startup boom"); sflag2[] = true end,
        on_shutdown = () -> begin error("shutdown boom"); dflag2[] = true end
    )

    @testset "startup with throwing hook does not rethrow" begin
        try
            @suppress_err begin 
                startup(lf2)
                @test true  # no exception bubbled out
            end
        catch e
            @test false
        end
        @test sflag2[] == false
    end

    @testset "shutdown with throwing hook does not rethrow" begin
        try
            @suppress_err begin 
                shutdown(lf2)
                @test true  # no exception bubbled out
            end
        catch e
            @test false
        end
        @test dflag2[] == false
    end
end

end # module
