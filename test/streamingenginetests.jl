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

@testset "drain_stream! keeps the first terminal" begin
    stream = EventStream(Channel{StreamEvent}(4), nothing)
    put!(stream.channel, FinalEvent("first"))
    put!(stream.channel, FinalEvent("second"))
    close(stream.channel)

    terminal = Streaming.drain_stream!(stream)
    @test terminal isa FinalEvent
    @test terminal.value == "first"

    # a producer failure after a result must not overwrite it either
    failed = EventStream(Channel{StreamEvent}(4), nothing)
    put!(failed.channel, FinalEvent("kept"))
    put!(failed.channel, ErrorEvent(ErrorException("late boom")))
    close(failed.channel)
    @test Streaming.drain_stream!(failed).value == "kept"
end

@testset "adopt_channel ends at the first marker and closes the source" begin
    source = Channel{Any}(4)
    put!(source, "tick")
    put!(source, FinalEvent("the answer"))
    put!(source, "after the marker")
    # deliberately left open: the framework must close it at the marker

    stream = Streaming.adopt_channel(source, nothing)
    events = collect(stream)

    # the marker never left the wrapper; it ended the stream and the framework
    # closed the source, so nothing after it was consumed
    @test length(events) == 2
    @test events[1].value == "tick"
    terminals = filter(event -> event isa FinalEvent, events)
    @test length(terminals) == 1
    @test terminals[1].value == "the answer"
    @test !isopen(source)
end

@testset "adopt_channel unwraps a failed producer task" begin
    source = Channel{Any}(2) do channel
        put!(channel, "before")
        error("raw boom")
    end

    stream = Streaming.adopt_channel(source, nothing)
    terminal = Streaming.drain_stream!(stream)
    @test terminal isa ErrorEvent
    @test terminal.error isa ErrorException
    @test sprint(showerror, terminal.error) == "raw boom"
end

@testset "a failing producer becomes an ErrorEvent" begin
    stream = make_stream() do s
        error("boom")
    end

    terminal = Streaming.drain_stream!(stream)
    @test terminal isa ErrorEvent
end

@testset "enqueue re-checks cancellation under the lock" begin
    stream = EventStream(Channel{StreamEvent}(4), nothing)
    Streaming.cancel_stream!(stream)
    # the pre-lock `check_cancelled` caller may race a cancellation; enqueue
    # refuses again once it holds the lock
    @test_throws StreamCancelled Streaming.enqueue!(stream, "late")
end

@testset "EventStream channel interface: fetch, take!, wait, bind" begin
    stream = EventStream(Channel{StreamEvent}(4), nothing)
    Streaming.emit(stream, "a")
    Streaming.emit(stream, "b")

    # `take!` pops; `fetch` peeks without consuming
    @test fetch(stream).value == "a"
    @test take!(stream).value == "a"
    @test take!(stream).value == "b"

    # `wait` returns once the stream has a value ready
    ready = EventStream(Channel{StreamEvent}(4), nothing)
    Streaming.emit(ready, "queued")
    @test isready(ready)
    wait(ready)
    @test take!(ready).value == "queued"

    # `bind` ties the handle's channel to a task and returns the handle
    bindable = EventStream(Channel{StreamEvent}(4), nothing)
    task = @async 1
    @test bind(bindable, task) === bindable
    wait(task)

    # already-normalized events pass through normalization untouched
    event = Streaming.FinalEvent("done")
    @test Streaming.normalize_event(stream, event) === event

    # the cancellation error prints its message
    @test sprint(showerror, StreamCancelled()) == "stream was cancelled"
    @test sprint(showerror, StreamCancelled("custom reason")) == "custom reason"
end

@testset "format_response rethrows a drained producer error" begin
    stream = make_stream() do s
        Streaming.emit(s, "first")
        error("drained boom")
    end

    # an internal request has no live connection, so the stream is drained and
    # a producer failure surfaces as a thrown error
    caught = try
        Streaming.format_response(Request("GET", "/internal"), stream)
        nothing
    catch error
        error
    end
    @test caught isa ErrorException
    @test occursin("drained boom", sprint(showerror, caught))
end

@testset "format_response adopts a raw channel" begin
    # the marker value is the buffered-fallback body; other values are dropped
    source = Channel{Any}(2)
    put!(source, "ignored")
    put!(source, FinalEvent(42))
    close(source)

    response = Streaming.format_response(Request("GET", "/internal"), source)
    @test response.status == 200
    @test String(response.body) == "42"

    # a channel that produced no marker answers null
    empty = Channel{Any}(1)
    close(empty)
    response = Streaming.format_response(Request("GET", "/internal"), empty)
    @test response.status == 200
    @test String(response.body) == "null"
end

@testset "format_response dispatch prefers EventStream over AbstractChannel" begin
    stream = make_stream(_ -> "done")
    method = which(Streaming.format_response, Tuple{Request, typeof(stream)})
    @test method.sig.parameters[3] === EventStream

    raw = Channel{Any}(1)
    close(raw)
    raw_method = which(Streaming.format_response, Tuple{Request, typeof(raw)})
    @test raw_method.sig.parameters[3] === AbstractChannel
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

@testset "cancel_stream! closes an adopted source" begin
    source = Channel{Any}(0)
    stream = Streaming.adopt_channel(source, nothing)
    @test stream.source === source

    Streaming.cancel_stream!(stream)
    @test !isopen(stream)
    @test !isopen(source)
    @test_throws InvalidStateException put!(source, "late")

    # `Base.close` is cancellation too, so it inherits the source close
    other_source = Channel{Any}(0)
    other = Streaming.adopt_channel(other_source, nothing)
    close(other)
    @test !isopen(other_source)
end

@testset "cancelling an adopted stream releases a blocked source producer" begin
    finished = Ref(false)
    caught = Ref{Any}(nothing)
    source = Channel{Any}(0)
    producer = @async begin
        try
            for i in 1:10_000
                put!(source, "tick $i")
            end
        catch error
            caught[] = error
        finally
            finished[] = true
        end
    end
    stream = Streaming.adopt_channel(source, nothing)
    sleep(0.05)  # let the pump and producer reach their blocked state
    Streaming.cancel_stream!(stream)

    deadline = time() + 5
    while time() < deadline && !finished[]
        sleep(0.001)
    end
    @test finished[]
    # the blocked `put!` was released by the close
    @test caught[] isa InvalidStateException
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
