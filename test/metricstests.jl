module MetricsTests 
using Test
using Dates 
using HTTP
using Oxygen

using ..Constants

using Oxygen.Core.Metrics:
    percentile, HTTPTransaction, TimeseriesRecord, get_history, push_history,
    group_transactions, get_transaction_metrics, recent_transactions,
    all_endpoint_metrics, server_metrics, error_distribution,
    prepare_timeseries_data, timeseries, series_format,
    bin_transactions, requests_per_unit, avg_latency_per_unit,
    endpoint_metrics, MetricsCache, register_metrics_cache!,
    unregister_metrics_cache!, metrics_cache, resync_metrics_cache!, uri_prefix,
    metrics_results

# Mock Data
const MOCK_TIMESTAMP = DateTime(2021, 1, 1, 12, 0, 0)
const MOCK_HTTP_TRANSACTION = HTTPTransaction("192.168.1.1", "/test", MOCK_TIMESTAMP, 0.5, true, 200, nothing)

# Helper Function to Create Mock Transactions
function create_mock_transactions(n::Int)
    [HTTPTransaction("192.168.1.$i", "/test/$i", MOCK_TIMESTAMP, 0.1 * i, i % 2 == 0, 200 + i, nothing) for i in 1:n]
end

const HISTORY = Oxygen.History(1_000_000)

function clear_history()
    empty!(HISTORY)
end

@testset "Metrics Module Tests" begin


    # Test for push_history and get_history
    @testset "History Management" begin
        clear_history()
        push_history(HISTORY, MOCK_HTTP_TRANSACTION)
        @test length(get_history(HISTORY)) == 1
        @test get_history(HISTORY)[1] === MOCK_HTTP_TRANSACTION
    end

    # Test for percentile
    @testset "Percentile Calculation" begin
        values = [1, 2, 3, 4, 5]
        @test percentile(values, 50) == 3
    end

    # Test for group_transactions
    @testset "Transaction Grouping" begin
        transactions = create_mock_transactions(10)
        grouped = group_transactions(transactions, 2)
        @test length(grouped) > 0
    end

    # Test for get_transaction_metrics
    @testset "Transaction Metrics Calculation" begin
        transactions = create_mock_transactions(10)
        metrics = get_transaction_metrics(transactions)
        @test metrics["total_requests"] == 10
        @test metrics["avg_latency"] > 0
    end

    # Test for recent_transactions
    @testset "Recent Transactions Retrieval" begin
        transactions = recent_transactions(get_history(HISTORY), Minute(15))
        @test all(t -> now(UTC) - t.timestamp <= Minute(15) + Second(1), transactions)
    end

    # Test for all_endpoint_metrics
    @testset "All Endpoint Metrics Calculation" begin
        metrics = all_endpoint_metrics(get_history(HISTORY))
        @test metrics isa Dict
    end

    # Test for server_metrics
    @testset "Server Metrics Calculation" begin
        metrics = server_metrics(get_history(HISTORY))
        @test metrics["total_requests"] >= 0
    end

    # Test for error_distribution
    @testset "Error Distribution Calculation" begin
        distribution = error_distribution(get_history(HISTORY))
        @test typeof(distribution) == Dict{String, Int}
    end


    # Test for timeseries and series_format
    @testset "Timeseries Conversion and Formatting" begin
        data = Dict(MOCK_TIMESTAMP => 1, MOCK_TIMESTAMP + Minute(1) => 2)
        ts = timeseries(data)
        formatted = series_format(ts)
        @test length(formatted) == 2
    end

    # Test for bin_transactions, requests_per_unit, and avg_latency_per_unit
    @testset "Transaction Binning and Metrics" begin
        bin_transactions(get_history(HISTORY), Minute(15))
        req_per_unit = requests_per_unit(get_history(HISTORY), Minute(1))
        avg_latency = avg_latency_per_unit(get_history(HISTORY), Minute(1))
        @test typeof(req_per_unit) == Dict{Dates.DateTime, Int}
        @test typeof(avg_latency) == Dict{Dates.DateTime, Number}
    end


    @testset "Recent Transactions with DateTime Lower Bound" begin
        clear_history()
        push_history(HISTORY, HTTPTransaction("192.168.1.1", "/test", DateTime(2023, 1, 1, 12), 0.5, true, 200, nothing))
        push_history(HISTORY, HTTPTransaction("192.168.1.2", "/test", DateTime(2023, 1, 1, 13), 0.5, true, 200, nothing))
        push_history(HISTORY, HTTPTransaction("192.168.1.3", "/test", DateTime(2023, 1, 1, 14), 0.5, true, 200, nothing))

        transactions = recent_transactions(get_history(HISTORY), DateTime(2023, 1, 1, 13))
        @test length(transactions) == 1
        @test all(t -> t.timestamp >= DateTime(2023, 1, 1, 13), transactions)
    end

    @testset "Endpoint Metrics Calculation" begin
        clear_history()
        push_history(HISTORY, HTTPTransaction("192.168.1.1", "/test", now(), 0.5, true, 200, nothing))
        push_history(HISTORY, HTTPTransaction("192.168.1.2", "/test", now(), 1.0, false, 500, "Error"))

        metrics = endpoint_metrics(get_history(HISTORY), "/test")

        @test metrics["total_requests"] == 2
        @test metrics["avg_latency"] == 0.75
        @test metrics["total_errors"] == 1
    end

    @testset "Incremental Metrics Cache" begin

        # Helper: build a transaction with a whole-second timestamp so cached
        # and uncached windowing agree exactly.
        tx(uri, second, duration, success=true; minute=0) = HTTPTransaction(
            "192.168.1.1", uri, DateTime(2023, 1, 1, 12, minute, second),
            duration, success, success ? 200 : 500, success ? nothing : "error")

        @testset "URI Prefix Grouping" begin
            for uri in ["/", "", "/test", "/a/b/c/d/e", "a/b/c", "/test/", "/a/b/c/d/e/f/g",
                        "/α/β/γ", "/日本/語/test/x", "/a/α/b/β/c", "/🚀/x/🚀/y/🚀"]
                for depth in 1:6
                    parts = split(uri, '/')
                    expected = join(parts[1:min(length(parts), depth + 1)], '/')
                    @test uri_prefix(uri, depth) == expected
                end
            end
        end

        @testset "Registration Validation" begin
            history = Oxygen.History(10)
            @test_throws ArgumentError register_metrics_cache!(history; max_depth=0)
            @test_throws ArgumentError register_metrics_cache!(history; max_depth=-1)
            @test_throws ArgumentError register_metrics_cache!(history; result_cache_size=0)
            @test isnothing(metrics_cache(history))
        end

        @testset "Unicode URIs Match Uncached Grouping" begin
            history = Oxygen.History(10)
            cache = register_metrics_cache!(history)
            try
                # Truncation lands right after multi-byte characters here, which
                # used to throw a StringIndexError out of push_history.
                push_history(history, tx("/α/β/γ/δ/x", 0, 0.5))
                push_history(history, tx("/日本/語/test/x", 1, 0.5))
                push_history(history, tx("/a/α/b/β/c", 2, 0.5))

                vector_history = get_history(history)
                @test server_metrics(cache, nothing) == server_metrics(vector_history, nothing)
                @test all_endpoint_metrics(cache, nothing) == all_endpoint_metrics(vector_history, nothing)
                @test error_distribution(cache, nothing) == error_distribution(vector_history, nothing)
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Cache Backfill" begin
            # Register the cache on a non-empty history, then keep pushing past
            # capacity so evictions exercise the backfilled ordering.
            history = Oxygen.History(3)
            push_history(history, tx("/test/a/b/c/1", 0, 0.25))
            push_history(history, tx("/test/a/b/c/2", 1, 0.5))
            push_history(history, tx("/test/a/b/c/3", 2, 0.75))
            cache = register_metrics_cache!(history)
            try
                push_history(history, tx("/test/a/b/c/4", 3, 1.0))
                push_history(history, tx("/test/a/b/c/5", 4, 0.5))

                vector_history = get_history(history)
                @test length(vector_history) == 3
                @test server_metrics(cache, nothing) == server_metrics(vector_history, nothing)
                @test all_endpoint_metrics(cache, nothing) == all_endpoint_metrics(vector_history, nothing)
                for unit in (Second, Minute)
                    @test requests_per_unit(cache, unit, nothing) == requests_per_unit(vector_history, unit, nothing)
                    @test avg_latency_per_unit(cache, unit, nothing) == avg_latency_per_unit(vector_history, unit, nothing)
                end
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Cache Matches Uncached Calculations" begin
            history = Oxygen.History(100)
            cache = register_metrics_cache!(history)
            try
                push_history(history, tx("/test/a", 0, 0.25))
                push_history(history, tx("/test/a", 0, 0.5, false))
                push_history(history, tx("/test/b", 1, 0.75))
                push_history(history, tx("/test/a/1", 1, 1.0))
                push_history(history, tx("/test/b", 2, 0.0))
                push_history(history, tx("/test/b/2", 2, 0.5, false))

                vector_history = get_history(history)

                @test server_metrics(cache, nothing) == server_metrics(vector_history, nothing)
                @test all_endpoint_metrics(cache, nothing) == all_endpoint_metrics(vector_history, nothing)
                @test error_distribution(cache, nothing) == error_distribution(vector_history, nothing)

                for unit in (Second, Minute)
                    @test requests_per_unit(cache, unit, nothing) == requests_per_unit(vector_history, unit, nothing)
                    @test avg_latency_per_unit(cache, unit, nothing) == avg_latency_per_unit(vector_history, unit, nothing)
                end

                # Repeated lookups with an unchanged history hit the memo table
                # and return equal values, but never expose the shared, memoized
                # Dict itself.
                @test server_metrics(cache, nothing) == server_metrics(cache, nothing)
                @test server_metrics(cache, nothing) !== server_metrics(cache, nothing)

                # DateTime bound (aligned to a whole second)
                bound = DateTime(2023, 1, 1, 12, 0, 1)
                for unit in (Second, Minute)
                    @test requests_per_unit(cache, unit, bound) == requests_per_unit(vector_history, unit, bound)
                    @test avg_latency_per_unit(cache, unit, bound) == avg_latency_per_unit(vector_history, unit, bound)
                end
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Cache Handles Evictions" begin
            history = Oxygen.History(3)
            cache = register_metrics_cache!(history)
            try
                for i in 1:6
                    uri = isodd(i) ? "/test/a/b/c/$i" : "/other/x/y/z/$i"
                    push_history(history, tx(uri, i, 0.25 * i, i != 5))
                end

                # The oldest transactions have been evicted, not the newest
                vector_history = get_history(history)
                @test length(vector_history) == 3
                @test first(vector_history).uri == "/other/x/y/z/6"
                @test last(vector_history).uri == "/other/x/y/z/4"

                @test server_metrics(cache, nothing) == server_metrics(vector_history, nothing)
                @test all_endpoint_metrics(cache, nothing) == all_endpoint_metrics(vector_history, nothing)
                @test error_distribution(cache, nothing) == error_distribution(vector_history, nothing)
                for unit in (Second, Minute)
                    @test requests_per_unit(cache, unit, nothing) == requests_per_unit(vector_history, unit, nothing)
                    @test avg_latency_per_unit(cache, unit, nothing) == avg_latency_per_unit(vector_history, unit, nothing)
                end

                # Evict everything from one group and make sure it disappears
                push_history(history, tx("/other/x/y/z/7", 7, 0.5))
                push_history(history, tx("/other/x/y/z/8", 8, 0.5))
                push_history(history, tx("/other/x/y/z/9", 9, 0.5))
                vector_history = get_history(history)
                @test all(t -> startswith(t.uri, "/other"), vector_history)
                @test all_endpoint_metrics(cache, nothing) == all_endpoint_metrics(vector_history, nothing)
                @test !haskey(all_endpoint_metrics(cache, nothing), "/test/a/b/c")
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Returned Results Are Copies" begin
            history = Oxygen.History(10)
            cache = register_metrics_cache!(history)
            try
                push_history(history, tx("/test/a", 0, 0.5))

                metrics = server_metrics(cache, nothing)
                metrics["total_requests"] = 999
                @test server_metrics(cache, nothing)["total_requests"] == 1

                endpoints = all_endpoint_metrics(cache, nothing)
                endpoints["/test/a"]["total_requests"] = 999
                @test all_endpoint_metrics(cache, nothing)["/test/a"]["total_requests"] == 1
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Failed Update Self-Heals" begin
            # A failed incremental update must not leave the cache permanently
            # stale; `push_history` rebuilds it from the history instead.
            history = Oxygen.History(1)
            cache = register_metrics_cache!(history)
            try
                # Out-of-band mutation leaves the cache empty while the history
                # holds a record, so the next eviction update underflows and fails.
                push!(history, tx("/stale", 0, 0.5))
                push_history(history, tx("/new", 1, 0.75))

                @test server_metrics(cache, nothing) == server_metrics(get_history(history), nothing)
                @test server_metrics(cache, nothing)["total_requests"] == 1
                @test all_endpoint_metrics(cache, nothing) ==
                      all_endpoint_metrics(get_history(history), nothing)
                @test error_distribution(cache, nothing) ==
                      error_distribution(get_history(history), nothing)
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Consistent Readout" begin
            history = Oxygen.History(10)
            cache = register_metrics_cache!(history)
            try
                for i in 1:5
                    push_history(history, tx("/test/$i", i, 0.5, i != 3))
                end

                results = metrics_results(cache)
                endpoints = all_endpoint_metrics(results)
                @test server_metrics(results)["total_requests"] ==
                      sum(m["total_requests"] for (_, m) in endpoints; init=0)
                @test server_metrics(results)["total_errors"] ==
                      sum(m["total_errors"] for (_, m) in endpoints; init=0)
                @test sum(values(requests_per_unit(results, Second, nothing)); init=0) ==
                      server_metrics(results)["total_requests"]

                # The cache-backed methods agree with the readout methods.
                @test server_metrics(cache, nothing) == server_metrics(results)
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Depth Symmetry and Empty Metrics" begin
            history = Oxygen.History(10)
            push_history(history, tx("/a/b/c/d", 0, 0.5, false))
            push_history(history, tx("/a/x", 1, 0.5, false))
            cache = register_metrics_cache!(history; max_depth=2)
            try
                # The uncached function now accepts the same depth as the cache.
                @test error_distribution(cache, nothing) ==
                      error_distribution(get_history(history), nothing; max_depth=2)
                @test Set(keys(error_distribution(get_history(history), nothing; max_depth=2))) ==
                      Set(["/a/b", "/a/x"])
                @test_throws ArgumentError error_distribution(cache, nothing; max_depth=4)
            finally
                unregister_metrics_cache!(history)
            end

            # Empty metrics carry `total_errors`, cached and uncached alike.
            empty_history = Oxygen.History(1)
            empty_cache = register_metrics_cache!(empty_history)
            try
                @test server_metrics(empty_cache, nothing)["total_errors"] == 0
                @test server_metrics(get_history(empty_history), nothing)["total_errors"] == 0
            finally
                unregister_metrics_cache!(empty_history)
            end
        end

        @testset "Coarser Bin Units" begin
            history = Oxygen.History(100)
            cache = register_metrics_cache!(history)
            try
                push_history(history, tx("/test/a", 0, 0.5))
                push_history(history, tx("/test/b", 1, 1.0, false))
                push_history(history, tx("/test/c", 2, 0.25))

                vector_history = get_history(history)
                for unit in (Second, Minute, Hour, Day)
                    @test requests_per_unit(cache, unit, nothing) == requests_per_unit(vector_history, unit, nothing)
                    @test avg_latency_per_unit(cache, unit, nothing) == avg_latency_per_unit(vector_history, unit, nothing)
                end

                # Sub-second units can't be derived from the retained bins.
                @test_throws ArgumentError requests_per_unit(cache, Millisecond, nothing)
                @test_throws ArgumentError avg_latency_per_unit(cache, Millisecond, nothing)
            finally
                unregister_metrics_cache!(history)
            end
        end

        @testset "Resync After External Mutation" begin
            history = Oxygen.History(10)
            cache = register_metrics_cache!(history)
            try
                push_history(history, tx("/test/a", 0, 0.5))
                push_history(history, tx("/test/a", 1, 1.0, false))

                # Mutate the history out of band: the aggregates go stale.
                empty!(history)
                push_history(history, tx("/test/b", 2, 2.0))
                @test server_metrics(cache, nothing) != server_metrics(get_history(history), nothing)

                # Rebuilding from the history makes the answers agree again.
                @test resync_metrics_cache!(cache) === cache
                @test server_metrics(cache, nothing) == server_metrics(get_history(history), nothing)
                @test all_endpoint_metrics(cache, nothing) == all_endpoint_metrics(get_history(history), nothing)
                @test error_distribution(cache, nothing) == error_distribution(get_history(history), nothing)
                for unit in (Second, Minute)
                    @test requests_per_unit(cache, unit, nothing) == requests_per_unit(get_history(history), unit, nothing)
                    @test avg_latency_per_unit(cache, unit, nothing) == avg_latency_per_unit(get_history(history), unit, nothing)
                end

                # The history-first method finds the registered cache.
                @test resync_metrics_cache!(history) === cache
            finally
                unregister_metrics_cache!(history)
            end
            @test isnothing(resync_metrics_cache!(history))
        end

        @testset "Registry Lifecycle" begin
            history = Oxygen.History(10)
            @test isnothing(metrics_cache(history))
            cache = register_metrics_cache!(history)
            @test metrics_cache(history) === cache
            unregister_metrics_cache!(history)
            @test isnothing(metrics_cache(history))
        end
    end


end

module A
    using Oxygen; @oxidize

    @get "/" function()
        text("server A")
    end
end

@testset "metrics collection & calculations" begin
    try 
        A.serve(host=HOST, port=PORT, async=true, show_banner=false, access_log=nothing)

        # send a couple requests so we can collect metrics
        for i in 1:10
            @test HTTP.get("$localhost/").status == 200
        end

        r = HTTP.get("$localhost/docs/metrics/data/15/null")
        @test r.status == 200

        data = json(r)
        @test data["server"]["total_requests"] == 10
        @test data["server"]["total_requests"] == 10
        @test data["server"]["total_errors"] == 0

        # The cache is fed by push_history, so metrics must pick up new traffic
        # without rescanning the history.
        @test HTTP.get("$localhost/").status == 200
        r = HTTP.get("$localhost/docs/metrics/data/15/null")
        @test r.status == 200
        data = json(r)
        @test data["server"]["total_requests"] == 11
        @test haskey(data["endpoints"], "/")

    finally
        A.terminate()
    end

end 

end
