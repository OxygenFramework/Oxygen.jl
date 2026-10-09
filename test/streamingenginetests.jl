module StreamingEngineTests

using Test
using Oxygen

const Streaming = Oxygen.Core.Streaming
const EventStream = Streaming.EventStream
const StreamEvent = Streaming.StreamEvent
const FinalEvent = Streaming.FinalEvent
const ErrorEvent = Streaming.ErrorEvent
const StreamCancelled = Streaming.StreamCancelled

make_stream(f; csize::Integer=Streaming.STREAM_BUFFER_SIZE) =
    Streaming.stream_events(f, nothing; csize=csize)

@testset "pump_stream forwards in order and stops on false" begin
    stream = make_stream() do s
        Streaming.emit(s, 1)
        Streaming.emit(s, 2)
        return "done"
    end

    seen = Any[]
    Streaming.pump_stream(stream, event -> begin
        push!(seen, event)
        return true
    end)

    @test length(seen) == 3
    @test seen[1].value == 1
    @test seen[2].value == 2
    @test seen[3] isa FinalEvent
    @test seen[3].value == "done"
end

@testset "polling pump forwards events and drains a closed stream" begin
    stream = make_stream() do s
        Streaming.emit(s, "a")
        return "done"
    end

    seen = Any[]
    Streaming.pump_stream(stream,
        event -> begin
            push!(seen, event)
            return true
        end;
        on_idle = () -> nothing, poll=0.001)

    @test length(seen) == 2
    @test seen[1].value == "a"
    @test seen[2] isa FinalEvent
end

@testset "polling pump exits when the raw channel is closed" begin
    stream = EventStream(Channel{StreamEvent}(4), nothing)
    finished = Ref(false)
    task = @async begin
        Streaming.pump_stream(stream,
            event -> true;
            on_idle = () -> nothing, poll=0.001)
        finished[] = true
    end

    sleep(0.05)
    close(stream.channel)
    wait(task)
    @test finished[]
end

@testset "drain_stream! returns the terminal event" begin
    stream = make_stream() do s
        Streaming.emit(s, 1)
        return "done"
    end

    terminal = Streaming.drain_stream!(stream)
    @test terminal isa FinalEvent
    @test terminal.value == "done"
end

@testset "a failing producer becomes an ErrorEvent" begin
    stream = make_stream() do s
        error("boom")
    end

    terminal = Streaming.drain_stream!(stream)
    @test terminal isa ErrorEvent
end

@testset "closing a stream cancels it and blocks late emits" begin
    stream = EventStream(Channel{StreamEvent}(4), nothing)
    Streaming.emit(stream, "first")
    close(stream)

    @test !isopen(stream)
    @test stream.cancel[]
    @test_throws StreamCancelled Streaming.emit(stream, "late")
    @test_throws StreamCancelled Streaming.check_cancelled(stream)

    @test take!(stream.channel).value == "first"
end

@testset "cancellation releases a blocked producer as StreamCancelled" begin
    started = Ref(false)
    caught = Ref{Any}(nothing)
    stream = make_stream(csize=1) do s
        try
            started[] = true
            for i in 1:10_000
                Streaming.emit(s, i)
            end
        catch error
            caught[] = error
        end
        return nothing
    end

    deadline = time() + 5
    while time() < deadline && !started[]
        sleep(0.001)
    end
    sleep(0.05)  # let the producer fill the buffer and block
    Streaming.cancel_stream!(stream)

    deadline = time() + 5
    while time() < deadline && isnothing(caught[])
        sleep(0.001)
    end
    @test caught[] isa StreamCancelled
end

@testset "channel interface: buffer state and readable show" begin
    stream = EventStream(Channel{StreamEvent}(4), nothing)

    @test Base.isbuffered(stream)
    @test Base.n_avail(stream) == 0
    open_repr = sprint(show, stream)
    @test occursin("EventStream{", open_repr)
    @test occursin("StreamEvent", open_repr)
    @test occursin("(open, 0 buffered)", open_repr)
    if isdefined(Base, :isfull)
        @test !Base.isfull(stream)
    end

    # fill the buffer to its capacity
    for value in 1:4
        Streaming.emit(stream, value)
    end
    @test Base.n_avail(stream) == 4
    @test occursin("(open, 4 buffered)", sprint(show, stream))
    if isdefined(Base, :isfull)
        @test Base.isfull(stream)
    end

    # closing is cancellation, but buffered events stay drainable
    close(stream)
    @test !isopen(stream)
    @test isready(stream)
    @test Base.n_avail(stream) == 4
    @test occursin("(cancelled, 4 buffered)", sprint(show, stream))

    # a producer that finishes normally shows as closed, not cancelled
    finished = make_stream(_ -> "done")
    @test Streaming.drain_stream!(finished) isa FinalEvent
    @test !isopen(finished)
    @test !finished.cancel[]
    @test occursin("(closed, 0 buffered)", sprint(show, finished))
end

end
