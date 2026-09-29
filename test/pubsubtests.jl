module PubSubTests

using Test
using Oxygen
using ..Constants

const PubSub = Oxygen.Core.PubSub
const Broker = PubSub.Broker

function queued(sub)::Vector
    values = []
    while isready(sub.queue)
        push!(values, take!(sub.queue))
    end
    return values
end

@testset "fan-out to N exact subscribers" begin
    broker = Broker{Int}()
    subs = [PubSub.subscribe!(broker, "ticks") for _ in 1:3]

    @test PubSub.subscribers(broker) == 3
    @test PubSub.publish!(broker, "ticks", 7) == 3
    for sub in subs
        @test queued(sub) == [7]
    end

    # A topic nobody watches delivers nowhere.
    @test PubSub.publish!(broker, "other", 1) == 0
end

@testset "exact, regex and predicate subscriptions" begin
    broker = Broker{Int}()
    exact = PubSub.subscribe!(broker, "orders/created")
    pattern = PubSub.subscribe!(broker, r"^orders/")
    predicate = PubSub.subscribe!(broker, value -> value > 10)

    @test PubSub.publish!(broker, "orders/created", 5) == 2
    @test queued(exact) == [5]
    @test queued(pattern) == [5]
    @test isempty(queued(predicate))

    @test PubSub.publish!(broker, "users/created", 50) == 1
    @test queued(predicate) == [50]
    @test isempty(queued(exact))

    @test PubSub.publish!(broker, "orders/created", 50) == 3
    @test queued(exact) == [50]
    @test queued(pattern) == [50]
    @test queued(predicate) == [50]
end

@testset "unsubscribe removes and closes" begin
    broker = Broker{Int}()
    sub = PubSub.subscribe!(broker, "a")

    @test PubSub.unsubscribe!(broker, sub) == true
    @test !isopen(sub)
    @test PubSub.publish!(broker, "a", 1) == 0
    @test PubSub.subscribers(broker) == 0
    @test PubSub.unsubscribe!(broker, sub) == false

    # Closing a subscription directly is equivalent.
    pattern = PubSub.subscribe!(broker, r"b")
    close(pattern)
    @test !isopen(pattern)
    @test PubSub.publish!(broker, "b", 1) == 0
    @test PubSub.subscribers(broker) == 0
end

@testset "delivery policies" begin
    # :drop_newest discards the incoming value and counts the drop
    broker = Broker{Int}()
    sub = PubSub.subscribe!(broker, "a"; csize=1, policy=:drop_newest)
    @test PubSub.publish!(broker, "a", 1) == 1
    @test PubSub.publish!(broker, "a", 2) == 0
    @test PubSub.drops(sub) == 1
    @test queued(sub) == [1]
    @test isopen(sub)

    # :drop_oldest makes room by discarding the oldest queued value
    broker = Broker{Int}()
    sub = PubSub.subscribe!(broker, "a"; csize=1, policy=:drop_oldest)
    @test PubSub.publish!(broker, "a", 1) == 1
    @test PubSub.publish!(broker, "a", 2) == 1
    @test queued(sub) == [2]
    @test PubSub.drops(sub) == 0

    # :disconnect closes the queue; buffered frames stay drainable and the
    # record is pruned
    broker = Broker{Int}()
    sub = PubSub.subscribe!(broker, "a"; csize=1, policy=:disconnect)
    @test PubSub.publish!(broker, "a", 1) == 1
    @test PubSub.publish!(broker, "a", 2) == 0
    @test !isopen(sub)
    @test Base.n_avail(sub.queue) == 1
    @test take!(sub.queue) == 1
    @test PubSub.subscribers(broker) == 0

    @test_throws ArgumentError PubSub.subscribe!(Broker{Int}(), "a"; policy=:nope)
end

@testset "callbacks fire after delivery and contain errors" begin
    broker = Broker{Int}()
    seen = Tuple{String,Int}[]
    PubSub.subscribe!(broker, "a"; callback=(topic, value) -> push!(seen, (topic, value)))

    @test PubSub.publish!(broker, "a", 1) == 1
    @test seen == [("a", 1)]

    # A failing callback neither breaks the publish nor starves a later one.
    PubSub.subscribe!(broker, "a"; callback=(_, _) -> error("boom"))
    other = Tuple{String,Int}[]
    PubSub.subscribe!(broker, "a"; callback=(topic, value) -> push!(other, (topic, value)))

    delivered = @test_logs (:warn, r"PubSub callback failed") PubSub.publish!(broker, "a", 2)
    @test delivered == 3
    @test other == [("a", 2)]
end

@testset "a callback may unsubscribe itself" begin
    broker = Broker{Int}()
    holder = Ref{Any}(nothing)
    calls = Ref(0)

    holder[] = PubSub.subscribe!(broker, "a"; callback=(_, _) -> begin
        calls[] += 1
        PubSub.unsubscribe!(broker, holder[])
    end)

    @test PubSub.publish!(broker, "a", 1) == 1
    @test calls[] == 1
    @test PubSub.subscribers(broker) == 0
    @test PubSub.publish!(broker, "a", 2) == 0
    @test calls[] == 1
end

@testset "a throwing matcher is contained" begin
    broker = Broker{Int}()
    PubSub.subscribe!(broker, _ -> error("bad predicate"); label="bad")
    healthy = PubSub.subscribe!(broker, _ -> true; label="healthy")

    delivered = @test_logs (:warn, r"PubSub matcher failed") PubSub.publish!(broker, "a", 1)
    @test delivered == 1
    @test queued(healthy) == [1]
    @test PubSub.subscribers(broker) == 2
end

@testset "the untyped broker accepts any value" begin
    broker = PubSub.Broker()
    sub = PubSub.subscribe!(broker, "any")

    @test PubSub.publish!(broker, "any", "text") == 1
    @test PubSub.publish!(broker, "any", Dict("a" => 1)) == 1
    @test queued(sub) == Any["text", Dict("a" => 1)]
end

@testset "unbuffered queues never block publishers" begin
    broker = Broker{Int}()
    sub = PubSub.subscribe!(broker, "a"; csize=0, policy=:drop_newest)

    # No taker is waiting, so the value is dropped rather than blocking.
    @test PubSub.publish!(broker, "a", 1) == 0
    @test PubSub.drops(sub) == 1
    @test PubSub.subscribers(broker) == 1
end

@testset "dead subscriptions are pruned opportunistically" begin
    broker = Broker{Int}(cap=2)
    first = PubSub.subscribe!(broker, "a")
    PubSub.subscribe!(broker, r"b")

    @test_throws PubSub.CapacityError PubSub.subscribe!(broker, "c")

    # subscribe! sweeps dead records before enforcing capacity
    close(first)
    third = PubSub.subscribe!(broker, "c")
    @test PubSub.subscribers(broker) == 2

    @test PubSub.publish!(broker, "a", 1) == 0     # pruned on publish
    @test PubSub.subscribers(broker) == 2
    @test PubSub.publish!(broker, "b", 2) == 1     # regex still live

    close(third)
    @test PubSub.subscribers(broker) == 1          # pruned on subscribers
end

@testset "close_all! ends every subscription" begin
    broker = Broker{Int}()
    subs = [PubSub.subscribe!(broker, "a") for _ in 1:2]
    pattern = PubSub.subscribe!(broker, r".*")

    PubSub.close_all!(broker)

    @test all(sub -> !isopen(sub), subs)
    @test !isopen(pattern)
    @test PubSub.publish!(broker, "a", 1) == 0
    @test PubSub.subscribers(broker) == 0
end

@testset "a pre-created channel keeps ack-first ordering" begin
    broker = Broker{Int}()
    queue = Channel{Int}(4)
    put!(queue, 0)  # the "ack" written before registration

    sub = PubSub.subscribe!(broker, "a"; channel=queue)
    @test PubSub.publish!(broker, "a", 1) == 1
    @test queued(sub) == [0, 1]

    @test_throws ArgumentError PubSub.subscribe!(Broker{Int}(), "a"; channel=Channel{String}(1))
end

@testset "concurrent publishers deliver without loss" begin
    if Threads.nthreads() == 1
        @test_skip "needs multiple threads"
    else
        broker = Broker{Int}()
        sub = PubSub.subscribe!(broker, "a"; csize=4096)

        publishers = 4
        per_publisher = 250
        tasks = [Threads.@spawn begin
                     for i in 1:per_publisher
                         PubSub.publish!(broker, "a", (p - 1) * per_publisher + i)
                     end
                 end for p in 1:publishers]
        foreach(wait, tasks)

        @test PubSub.subscribers(broker) == 1
        received = Int[take!(sub.queue) for _ in 1:(publishers * per_publisher)]
        @test sort(received) == collect(1:(publishers * per_publisher))
    end
end

end
