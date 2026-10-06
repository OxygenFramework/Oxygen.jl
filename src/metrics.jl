module Metrics

using HTTP
using JSON
using Dates
using DataStructures
using Statistics
using RelocatableFolders
using LRUCache: LRU
using ..Util
using ..Types

export MetricsMiddleware, get_history, push_history, 
    server_metrics,
    all_endpoint_metrics, 
    capture_metrics, bin_and_count_transactions,
    bin_transactions, requests_per_unit, avg_latency_per_unit,
    timeseries, series_format, error_distribution,
    prepare_timeseries_data,
    MetricsCache, register_metrics_cache!, unregister_metrics_cache!, metrics_cache,
    resync_metrics_cache!, metrics_results

struct TimeseriesRecord 
    timestamp::DateTime
    value::Number
end

# ---------------------------------------------------------------------------
# Incremental metrics cache
#
# The metrics dashboard polls its data endpoint on a short interval. Recomputing
# every metric over the entire transaction history on each poll gets slower as
# the history grows, so instead we maintain a handful of aggregates that are
# updated once per transaction as it enters (or leaves) the history, and
# memoize a single consistent readout of them, keyed by the history version.
# Queries then read the aggregates instead of rescanning the history.
#
# `metrics_results` snapshots the whole cache under one lock acquisition and
# memoizes the computed metrics plus a copy of the per-second bins; every
# dashboard output for a request is derived from that one version, and repeated
# queries at the same version are served from the memo table. The returned
# Dicts are copies, so callers can't mutate the cached results. Bin aggregation
# is done outside the lock from the copied bins, so queries don't stall pushes.
#
# Lifetime server/endpoint metrics match the uncached functions (floating-point
# averages can differ in the last ulp because values are summed in a different
# order); time-binned queries are accurate to within one second at the window
# edge because only whole-second bins are retained (see `bin_cutoff`).
#
# Cost: a full recompute follows new traffic (an exact percentile needs the
# retained transactions), so it is O(history); repeated queries at the same
# version are served from the memo table, and the time-binned queries only walk
# the copied per-second bins.
# ---------------------------------------------------------------------------

"""
Per-endpoint (or whole-server) latency accumulator.

`durations` holds only the non-zero durations (matching `get_transaction_metrics`)
in insertion order. It's a deque so the oldest duration can be dropped in O(1)
when the history evicts a transaction.
"""
mutable struct LatencyStats
    total_requests :: Int
    total_errors   :: Int
    durations      :: Deque{Float64}
end

LatencyStats() = LatencyStats(0, 0, Deque{Float64}())

function reset!(stats::LatencyStats)
    stats.total_requests = 0
    stats.total_errors = 0
    empty!(stats.durations)
    return stats
end

"""
Per-second request/latency bucket. `count` includes every transaction while
`sum` accumulates every duration (including zero-duration records) so that
`avg_latency_per_unit` can be derived exactly.

Immutable so a snapshot can copy stored buckets cheaply: updates replace the
bucket instead of mutating it.
"""
struct BinStats
    count :: Int
    sum   :: Float64
end

"""
Incremental aggregate over a `History`. One cache is created per running server
(see `register_metrics_cache!`) and kept in sync by `push_history`.

All mutations of `cache.history` must go through `push_history` (under the same
lock the server uses to serialize pushes); if something mutates the history
directly, call `resync_metrics_cache!` afterwards to rebuild the aggregates.
"""
mutable struct MetricsCache
    lock      :: ReentrantLock
    history   :: History
    max_depth :: Int
    version   :: UInt64
    # The lock that serializes pushes into `history`, when the cache was
    # registered with one. Used by `resync_metrics_cache!` to rebuild safely.
    history_lock :: Nullable{ReentrantLock}
    # lifetime aggregates
    server    :: LatencyStats
    groups    :: Dict{String, LatencyStats}
    # per-second bins; minute (and other) units are derived from these
    seconds   :: Dict{DateTime, BinStats}
    # bounded memo table of computed results: key => (version, result)
    results   :: LRU{Any, Tuple{UInt64, Any}}
end

const METRICS_CACHES      = IdDict{History, MetricsCache}()
const METRICS_CACHES_LOCK = ReentrantLock()

"""
    register_metrics_cache!(history; max_depth=4, result_cache_size=8, history_lock=nothing)

Attach an incremental metrics cache to `history`. Any transactions already in
the history are folded in up front (normally the history is empty because the
cache is registered before the server starts). Returns the cache.

Pass the server's `history_lock` to make registration safe even if it happens
while requests are being served: without it, a concurrent `push_history` can
slip between seeding and publication and be missed. The lock is stored on the
cache and reused by `resync_metrics_cache!` when no explicit lock is passed.
"""
function register_metrics_cache!(history::History; max_depth::Int=4, result_cache_size::Int=8,
                                 history_lock::Nullable{ReentrantLock}=nothing)
    if max_depth < 1
        throw(ArgumentError("max_depth must be >= 1, got $max_depth"))
    end
    if result_cache_size < 1
        throw(ArgumentError("result_cache_size must be >= 1, got $result_cache_size"))
    end

    cache = MetricsCache(
        ReentrantLock(),
        history,
        max_depth,
        0,
        history_lock,
        LatencyStats(),
        Dict{String, LatencyStats}(),
        Dict{DateTime, BinStats}(),
        LRU{Any, Tuple{UInt64, Any}}(maxsize=result_cache_size),
    )

    install = function()
        lock(cache.lock) do
            rebuild_cache!(cache)
        end
        lock(METRICS_CACHES_LOCK) do
            METRICS_CACHES[history] = cache
        end
        return cache
    end

    return isnothing(history_lock) ? install() : lock(install, history_lock)
end

# Rebuild the aggregates from the current contents of `cache.history`. The
# caller must hold `cache.lock` and guarantee the history is not mutated
# concurrently (e.g. by holding the server's `history_lock`).
function rebuild_cache!(cache::MetricsCache)
    reset!(cache.server)
    empty!(cache.groups)
    empty!(cache.seconds)
    empty!(cache.results)

    # Iterate oldest to newest so the duration deques stay in insertion order
    # (evictions pop the front, which must be the oldest retained record).
    for index in length(cache.history):-1:1
        add_transaction!(cache, cache.history[index])
    end
    cache.version += 1
    return cache
end

"""
    resync_metrics_cache!(cache::MetricsCache; history_lock=nothing)
    resync_metrics_cache!(history::History; history_lock=nothing)

Rebuild the cache's aggregates from the current contents of its history. Use
this after mutating a history without going through `push_history` (for example
after `empty!`), which would otherwise leave stale aggregates behind. Pass the
`history_lock` that serializes pushes, or call while the server is quiescent;
otherwise the rebuild can race with a concurrent push. When no explicit lock is
passed, the lock stored at registration time (if any) is used, so a cache
registered through `serve` rebuilds safely by default. The `History` method
returns the cache, or `nothing` when no cache is registered.
"""
function resync_metrics_cache!(cache::MetricsCache; history_lock::Nullable{ReentrantLock}=nothing)
    work = function()
        lock(cache.lock) do
            rebuild_cache!(cache)
        end
        return cache
    end
    effective_lock = isnothing(history_lock) ? cache.history_lock : history_lock
    return isnothing(effective_lock) ? work() : lock(work, effective_lock)
end

function resync_metrics_cache!(history::History; history_lock::Nullable{ReentrantLock}=nothing)
    cache = metrics_cache(history)
    if isnothing(cache)
        return nothing
    end
    return resync_metrics_cache!(cache; history_lock=history_lock)
end

"""
    unregister_metrics_cache!(history)

Detach and drop the cache associated with `history` (called on server shutdown).
"""
function unregister_metrics_cache!(history::History)
    lock(METRICS_CACHES_LOCK) do
        delete!(METRICS_CACHES, history)
    end
    return nothing
end

"""
    metrics_cache(history) :: Nullable{MetricsCache}

Return the cache registered for `history`, or `nothing` when metrics caching
isn't active for this history.
"""
function metrics_cache(history::History) :: Nullable{MetricsCache}
    lock(METRICS_CACHES_LOCK) do
        return get(METRICS_CACHES, history, nothing)
    end
end

"""
    uri_prefix(uri::String, max_depth::Int) :: String

Return the same URI prefix that `group_transactions` groups by (for
`max_depth >= 1`): the first `max_depth` path segments including the leading
`/`. Allocates only the final substring (no intermediate `split` vector) and
slices on character boundaries, so multi-byte URIs are handled correctly.
"""
function uri_prefix(uri::String, max_depth::Int)
    if max_depth > 0
        seen = 0
        for (index, char) in pairs(uri)
            if char == '/'
                seen += 1
                if seen == max_depth + 1
                    # `index` is a byte index; step back one *character* so a
                    # multi-byte character before the slash doesn't produce an
                    # invalid StringIndex.
                    return uri[1:prevind(uri, index)]
                end
            end
        end
    end
    return uri
end

function add_transaction!(cache::MetricsCache, transaction::HTTPTransaction)
    # Derive the grouping/bin keys *before* touching any aggregate: if this
    # throws (e.g. because of a malformed URI), the cache is left untouched
    # instead of partially updated with a version that never advances.
    prefix = uri_prefix(transaction.uri, cache.max_depth)
    bin_key = floor(transaction.timestamp, Second)

    add_transaction!(cache.server, transaction)

    stats = get!(cache.groups, prefix) do
        LatencyStats()
    end
    add_transaction!(stats, transaction)

    bin = get(cache.seconds, bin_key, nothing)
    cache.seconds[bin_key] = isnothing(bin) ? BinStats(1, transaction.duration) :
        BinStats(bin.count + 1, bin.sum + transaction.duration)

    return cache
end

function add_transaction!(stats::LatencyStats, transaction::HTTPTransaction)
    stats.total_requests += 1
    if !transaction.success
        stats.total_errors += 1
    end

    duration = transaction.duration
    if duration != 0.0
        push!(stats.durations, duration)
    end

    return stats
end

function remove_transaction!(cache::MetricsCache, transaction::HTTPTransaction)
    remove_transaction!(cache.server, transaction)

    prefix = uri_prefix(transaction.uri, cache.max_depth)
    stats = get(cache.groups, prefix, nothing)
    if !isnothing(stats)
        remove_transaction!(stats, transaction)
        if stats.total_requests == 0
            delete!(cache.groups, prefix)
        end
    end

    bin_key = floor(transaction.timestamp, Second)
    bin = get(cache.seconds, bin_key, nothing)
    if !isnothing(bin)
        remaining = bin.count - 1
        remaining <= 0 ? delete!(cache.seconds, bin_key) :
            (cache.seconds[bin_key] = BinStats(remaining, bin.sum - transaction.duration))
    end

    return cache
end

function remove_transaction!(stats::LatencyStats, transaction::HTTPTransaction)
    stats.total_requests -= 1
    if !transaction.success
        stats.total_errors -= 1
    end

    duration = transaction.duration
    if duration != 0.0
        # The evicted transaction is the oldest one in the history, therefore it
        # is also the oldest retained transaction in its group and its duration
        # sits at the front of the deque. If the invariant was broken (e.g. the
        # history was mutated out of band), the pop throws and `push_history`
        # rebuilds the cache from the history.
        popfirst!(stats.durations)
    end

    return stats
end

function update_metrics_cache!(cache::MetricsCache, transaction::HTTPTransaction, evicted::Nullable{HTTPTransaction})
    lock(cache.lock) do
        if !isnothing(evicted)
            remove_transaction!(cache, evicted)
        end
        add_transaction!(cache, transaction)
        cache.version += 1
    end
    return nothing
end

struct LatencySnapshot
    total_requests :: Int
    total_errors   :: Int
    durations      :: Vector{Float64}
end

function snapshot(stats::LatencyStats) :: LatencySnapshot
    return LatencySnapshot(stats.total_requests, stats.total_errors, collect(stats.durations))
end

"""
Recompute the metrics returned by `get_transaction_metrics` from a snapshot.
Percentile selection is O(n) (`partialsort!`) instead of O(n log n).
"""
function metrics_from_snapshot(snapshot::LatencySnapshot)
    total_requests = snapshot.total_requests
    total_errors = snapshot.total_errors

    if total_requests == 0
        return Dict(
            "total_requests" => 0,
            "total_errors" => 0,
            "avg_latency" => 0,
            "min_latency" => 0,
            "max_latency" => 0,
            "percentile_latency_95th" => 0,
            "error_rate" => 0
        )
    end

    latencies = snapshot.durations
    has_records = !isempty(latencies)

    avg_latency = has_records ? mean(latencies) : 0
    min_latency = has_records ? minimum(latencies) : 0
    max_latency = has_records ? maximum(latencies) : 0
    percentile_95_latency = has_records ? partialsort!(latencies, ceil(Int, 95 / 100 * length(latencies))) : 0
    error_rate = total_errors / total_requests

    return Dict(
        "total_requests" => total_requests,
        "total_errors" => total_errors,
        "avg_latency" => avg_latency,
        "min_latency" => min_latency,
        "max_latency" => max_latency,
        "percentile_latency_95th" => percentile_95_latency,
        "error_rate" => error_rate
    )
end

"""
Look up a computed result in the cache's memo table, recomputing it when the
history changed since it was stored. `snapshot_fn` runs while holding the cache
lock (it must capture the state the result is derived from); `compute_fn` runs
outside the lock so pushes are never stalled by a percentile calculation.
"""
function cached_metrics_result(cache::MetricsCache, key::Any, snapshot_fn::Function, compute_fn::Function)
    cached = lock(cache.lock) do
        entry = get(cache.results, key, nothing)
        if !isnothing(entry) && entry[1] == cache.version
            return entry[2]
        end
        return nothing
    end
    if !isnothing(cached)
        return cached
    end

    version, data = lock(cache.lock) do
        return (cache.version, snapshot_fn())
    end

    result = compute_fn(data)

    lock(cache.lock) do
        # Only publish the result if the aggregates didn't move while computing.
        if cache.version == version
            cache.results[key] = (version, result)
        end
    end

    return result
end

"""
A consistent, read-only view of the cache at one history version.

`server`, `endpoints`, and `errors` are the computed (memoized) metrics values;
`bins` is a copy of the retained per-second bins. All fields describe the same
version, so a dashboard response built from one `MetricsResults` can't mix
traffic from different versions. Treat every field as read-only: the object is
shared by all queries at this version.
"""
struct MetricsResults
    server    :: Dict{String, Any}
    endpoints :: Dict{String, Dict{String, Any}}
    errors    :: Dict{String, Int}
    bins      :: Dict{DateTime, BinStats}
end

# Capture everything a readout needs under the cache lock. The returned tuple is
# passed to `compute_metrics_results` outside the lock.
function snapshot_aggregates(cache::MetricsCache)
    server = snapshot(cache.server)
    groups = Dict{String, LatencySnapshot}(prefix => snapshot(stats) for (prefix, stats) in cache.groups)

    # `BinStats` is immutable, so a shallow Dict copy can't observe later updates
    # and is much cheaper than rebuilding a vector of tuples.
    bins = copy(cache.seconds)
    return (server, groups, bins)
end

function compute_metrics_results(data) :: MetricsResults
    server, groups, bins = data

    endpoints = Dict{String, Dict{String, Any}}()
    for (prefix, group) in groups
        endpoints[prefix] = Dict{String, Any}(metrics_from_snapshot(group))
    end

    errors = Dict{String, Int}()
    for (prefix, metrics) in endpoints
        failures = metrics["total_errors"]
        if failures > 0
            errors[prefix] = failures
        end
    end

    return MetricsResults(Dict{String, Any}(metrics_from_snapshot(server)), endpoints, errors, bins)
end

"""
    metrics_results(cache::MetricsCache) :: MetricsResults

Return the cache's computed metrics together with the retained per-second bins,
all captured at one history version. The result is memoized, so repeated calls
at an unchanged version are cheap, and every dashboard output for a request can
be derived from the same immutable readout. Pass it to `server_metrics`,
`all_endpoint_metrics`, `error_distribution`, `requests_per_unit`, or
`avg_latency_per_unit`.
"""
function metrics_results(cache::MetricsCache)
    return cached_metrics_result(cache, (:results,),
        () -> snapshot_aggregates(cache),
        compute_metrics_results)
end

"""
Copy a metrics Dict before handing it to a caller: memoized metrics results are
shared between callers, and mutating a returned Dict would corrupt the cache.
"""
copy_metrics_dict(data::Dict) =
    Dict(key => (value isa AbstractDict ? copy(value) : value) for (key, value) in data)

"""
    push_history(history, transaction)

Insert `transaction` at the front of `history`, evicting the oldest record once
the history is at `capacity(history)`, and keep any registered metrics cache in
sync. The deque itself is not locked, so concurrent pushes must be serialized by
the caller (the server holds its history lock around this call). Metrics
bookkeeping errors are logged and swallowed so they can never fail a request.
"""
function push_history(history::History, transaction::HTTPTransaction)
    cache = metrics_cache(history)
    evicted = nothing
    try
        # Keep the newest `capacity(history)` transactions: once the deque is
        # full, drop the oldest record before inserting the new one.
        if length(history) >= capacity(history)
            evicted = last(history)
            pop!(history)
        end
        try
            pushfirst!(history, transaction)
        catch
            # Put the evicted record back so a failed push doesn't lose it.
            if !isnothing(evicted)
                try
                    push!(history, evicted)
                catch restore_error
                    @warn "Failed to restore evicted transaction: $restore_error"
                end
            end
            rethrow()
        end
    catch error
        @warn "Failed to push transaction into our history: $error"
        return nothing
    end

    # Keep the incremental aggregates in sync when metrics caching is active.
    # A metrics-cache failure must never fail the request that produced the
    # transaction, so it is reported and the cache is rebuilt from the history
    # to heal any partially applied update.
    try
        if !isnothing(cache)
            update_metrics_cache!(cache, transaction, evicted)
        end
    catch error
        @warn "Failed to update the metrics cache: $error"
        if !isnothing(cache)
            try
                resync_metrics_cache!(cache)
            catch rebuild_error
                @warn "Failed to rebuild the metrics cache: $rebuild_error"
            end
        end
    end
    return nothing
end

"""
    get_history(history) :: Vector{HTTPTransaction}

Return a snapshot of `history` with the newest transaction first. The deque is
not locked; readers that may race with request handling should hold the
server's `history_lock` (see `safe_get_transactions` in `core.jl`).
"""
function get_history(history::History) :: Vector{HTTPTransaction}
    return collect(history)
end

# Helper function to calculate percentile
function percentile(values, p)
    index = ceil(Int, p / 100 * length(values))
    # `partialsort` selects the same element as sorting and indexing, in O(n)
    # expected time instead of O(n log n).
    return partialsort(values, index)
end

# Function to group HTTPTransaction objects by URI prefix with a maximum depth limit
function group_transactions(transactions::Vector{HTTPTransaction}, max_depth::Int)
    # Create a dictionary to store the grouped transactions
    grouped_transactions = Dict{String, Vector{HTTPTransaction}}()

    for transaction in transactions
        # Split the URI by '/' to get the segments
        uri_parts = split(transaction.uri, '/')

        # Determine the depth and create the prefix
        depth = min(length(uri_parts), max_depth + 1)
        prefix = join(uri_parts[1:depth], '/')

        # Check if the prefix exists in the dictionary, if not, create an empty vector
        if !haskey(grouped_transactions, prefix)
            grouped_transactions[prefix] = []
        end

        # Append the transaction to the corresponding prefix
        push!(grouped_transactions[prefix], transaction)
    end

    return grouped_transactions
end


### Helper function to calculate metrics for a set of transactions
function get_transaction_metrics(transactions::Vector{HTTPTransaction})
    if isempty(transactions)
        return Dict(
            "total_requests" => 0,
            "total_errors" => 0,
            "avg_latency" => 0,
            "min_latency" => 0,
            "max_latency" => 0,
            "percentile_latency_95th" => 0,
            "error_rate" => 0
        )
    end

    total_requests = length(transactions)
    latencies = [t.duration for t in transactions if t.duration != 0.0]
    has_records = !isempty(latencies)

    avg_latency = has_records ? mean(latencies) : 0
    min_latency = has_records ? minimum(latencies) : 0
    max_latency = has_records ? maximum(latencies) : 0
    percentile_95_latency = has_records ? percentile(latencies, 95) : 0
    total_errors = count(t -> !t.success, transactions)
    error_rate = total_requests > 0 ? total_errors / total_requests : 0

    return Dict(
        "total_requests" => total_requests,
        "total_errors" => total_errors,
        "avg_latency" => avg_latency,
        "min_latency" => min_latency,
        "max_latency" => max_latency,
        "percentile_latency_95th" => percentile_95_latency,
        "error_rate" => error_rate
    )
end

### Helper function to group transactions by endpoint

function recent_transactions(history::Vector{HTTPTransaction}, ::Nothing) :: Vector{HTTPTransaction}
    return history
end

function recent_transactions(history::Vector{HTTPTransaction}, lower_bound::Dates.Period) :: Vector{HTTPTransaction}
    current_time = now(UTC)
    adjusted = lower_bound + Second(1)
    return filter(t -> current_time - t.timestamp <= adjusted, history) 
end

# Needs coverage
function recent_transactions(history::Vector{HTTPTransaction}, lower_bound::Dates.DateTime) :: Vector{HTTPTransaction}
    adjusted = lower_bound + Second(1)
    return filter(t -> t.timestamp >= adjusted, history) 
end

"""
Group transactions by URI depth with a maximum depth limit using the function
"""
function all_endpoint_metrics(history::Vector{HTTPTransaction}, lower_bound=Minute(15); max_depth=4)
    transactions = recent_transactions(history, lower_bound)    
    groups = group_transactions(transactions, max_depth)
    return Dict(k => get_transaction_metrics(v) for (k,v) in groups)
end


function server_metrics(history::Vector{HTTPTransaction}, lower_bound=Minute(15))
    transactions = recent_transactions(history, lower_bound)
    get_transaction_metrics(transactions)
end

# Needs coverage
function endpoint_metrics(history::Vector{HTTPTransaction}, endpoint_uri::String)
    endpoint_transactions = filter(t -> t.uri == endpoint_uri, history)
    return get_transaction_metrics(endpoint_transactions)
end

function error_distribution(history::Vector{HTTPTransaction}, lower_bound=Minute(15); max_depth::Int=4)
    metrics = all_endpoint_metrics(history, lower_bound; max_depth=max_depth)
    failed_counts = Dict{String, Int}()
    for (group_prefix, transaction_metrics) in metrics
        failures = transaction_metrics["total_errors"]
        if failures > 0
            failed_counts[group_prefix] = get(failed_counts, group_prefix, 0) + failures
        end
    end
    return failed_counts
end

function prepare_timeseries_data()
    function(binned_records::Dict)
        binned_records |> timeseries |> series_format
    end
end

"""
Convert a dictionary of timeseries data into an array of sorted records
"""
function timeseries(data) :: Vector{TimeseriesRecord}
    # Convert the dictionary into an array of [timestamp, value] pairs
    timestamp_value_pairs = [TimeseriesRecord(k, v) for (k, v) in data]
    # Sort the array based on the timestamps (the first element in each pair)
    return sort(timestamp_value_pairs, by=x->x.timestamp)    
end


"""
Convert a TimeseriesRecord into a matrix format that works better with apex charts
"""
function series_format(data::Vector{TimeseriesRecord}) :: Vector{Vector{Union{DateTime,Number}}}
    return [[item.timestamp, item.value] for item in data]
end

"""
Helper function to group transactions within a given timeframe
"""
function bin_transactions(history::Vector{HTTPTransaction}, lower_bound=Minute(15), unit=Minute, strategy=nothing) :: Dict{DateTime,Vector{HTTPTransaction}}
    transactions = recent_transactions(history, lower_bound)
    binned = Dict{DateTime, Vector{HTTPTransaction}}()
    for t in transactions
        # create bin's based on the given unit
        bin_value = floor(t.timestamp, unit)
        if !haskey(binned, bin_value)
            binned[bin_value] = [t]
        else
            push!(binned[bin_value], t)
        end
        
        if !isnothing(strategy)
            strategy(bin_value, t)
        end
    end
    return binned
end

function requests_per_unit(history::Vector{HTTPTransaction}, unit, lower_bound=Minute(15))
    bin_counts = Dict{DateTime, Int}()
    function count_transactions(bin, transaction) 
        bin_counts[bin] = get(bin_counts, bin, 0) + 1
    end
    bin_transactions(history, lower_bound, unit, count_transactions)
    return bin_counts
end

"""
Return the average latency per minute for the server
"""
function avg_latency_per_unit(history::Vector{HTTPTransaction}, unit, lower_bound=Minute(15))
    bin_counts = Dict{DateTime, Vector{Number}}()
    function strategy(bin, transaction) 
        if haskey(bin_counts, bin)
            push!(bin_counts[bin], transaction.duration)
        else 
            bin_counts[bin] = [transaction.duration]
        end
    end
    bin_transactions(history, lower_bound, unit, strategy)
    averages = Dict{DateTime, Number}()
    for (k,v) in bin_counts
        averages[k] = mean(v)
    end
    return averages
end


# ---------------------------------------------------------------------------
# Cache-aware query methods
#
# These mirror the vector-based functions above but read the incremental
# aggregates instead of rescanning the whole history. They are used by the
# metrics dashboard endpoint; the uncached methods remain available (and
# unchanged) for direct callers.
# ---------------------------------------------------------------------------

"""
    server_metrics(results::MetricsResults)
    server_metrics(cache::MetricsCache, ::Nothing)

Server-wide metrics computed from the incremental cache. Equivalent to
`server_metrics(get_history(cache.history), nothing)`. The returned Dict is a
copy; mutating it is safe.
"""
function server_metrics(results::MetricsResults)
    return copy_metrics_dict(results.server)
end

function server_metrics(cache::MetricsCache, ::Nothing)
    return server_metrics(metrics_results(cache))
end

"""
    all_endpoint_metrics(results::MetricsResults)
    all_endpoint_metrics(cache::MetricsCache, ::Nothing; max_depth=cache.max_depth)

Per-endpoint metrics computed from the incremental cache. Equivalent to
`all_endpoint_metrics(get_history(cache.history), nothing; max_depth=max_depth)`
when `max_depth` matches the depth the cache was registered with. The returned
Dicts are copies; mutating them is safe.
"""
function all_endpoint_metrics(results::MetricsResults)
    return copy_metrics_dict(results.endpoints)
end

function all_endpoint_metrics(cache::MetricsCache, ::Nothing; max_depth::Int=cache.max_depth)
    if max_depth != cache.max_depth
        throw(ArgumentError(
            "This cache was registered with max_depth=$(cache.max_depth); register a cache with max_depth=$max_depth to query that depth"))
    end

    return all_endpoint_metrics(metrics_results(cache))
end

"""
    error_distribution(results::MetricsResults)
    error_distribution(cache::MetricsCache, ::Nothing; max_depth=cache.max_depth)

Error counts per endpoint group, derived from the cached endpoint metrics.
"""
function error_distribution(results::MetricsResults)
    return copy(results.errors)
end

function error_distribution(cache::MetricsCache, ::Nothing; max_depth::Int=cache.max_depth)
    if max_depth != cache.max_depth
        throw(ArgumentError(
            "This cache was registered with max_depth=$(cache.max_depth); register a cache with max_depth=$max_depth to query that depth"))
    end

    return error_distribution(metrics_results(cache))
end

function bin_cutoff(lower_bound)
    if isnothing(lower_bound)
        return nothing
    elseif lower_bound isa Dates.Period
        # Mirrors recent_transactions(history, ::Period): timestamps must be
        # within `lower_bound + 1s` of the current time. Callers compare this
        # cutoff against whole-second bins, so the effective window edge can be
        # up to one second looser than the uncached timestamp filter.
        return now(UTC) - lower_bound - Second(1)
    elseif lower_bound isa DateTime
        # Mirrors recent_transactions(history, ::DateTime)
        return lower_bound + Second(1)
    else
        throw(ArgumentError("Unsupported lower bound: $(typeof(lower_bound))"))
    end
end

"""
Aggregate the retained per-second bins into `unit`-sized bins. Any fixed period
of one second or longer (`Second`, `Minute`, `Hour`, `Day`, ...) can be derived;
finer units aren't retained. Returns `Dict{DateTime, BinStats}`.

The bins are copied under the cache lock by `metrics_results`, so aggregation
runs lock-free from that snapshot and a query never stalls a push.

The lower bound is floored to a whole second and bins are filtered whole-bucket,
so the first bin of the window can include transactions up to one second older
than the uncached `recent_transactions` filter would; interior bins are exact.
"""
function bin_totals(results::MetricsResults, unit::Type{<:Dates.FixedPeriod}, lower_bound)
    if Second(1) > unit(1)
        throw(ArgumentError(
            "Cached metrics only support fixed periods of one second or longer, got $unit"))
    end

    cutoff = bin_cutoff(lower_bound)
    floor_cutoff = isnothing(cutoff) ? nothing : floor(cutoff, Second)

    totals = Dict{DateTime, Tuple{Int, Float64}}()
    for (second, bin) in results.bins
        if !isnothing(floor_cutoff) && second < floor_cutoff
            continue
        end
        bin_key = unit === Second ? second : floor(second, unit)
        previous = get(totals, bin_key, (0, 0.0))
        totals[bin_key] = (previous[1] + bin.count, previous[2] + bin.sum)
    end
    return Dict{DateTime, BinStats}(bin => BinStats(count, sum) for (bin, (count, sum)) in totals)
end

function bin_totals(cache::MetricsCache, unit::Type{<:Dates.FixedPeriod}, lower_bound)
    return bin_totals(metrics_results(cache), unit, lower_bound)
end

"""
    requests_per_unit(results::MetricsResults, unit, lower_bound)
    requests_per_unit(cache::MetricsCache, unit, lower_bound)

Cached equivalent of `requests_per_unit(get_history(cache.history), unit, lower_bound)`.
As with all cached time-series queries, the window edge is accurate to within
one second (see `bin_totals`).
"""
function requests_per_unit(results::MetricsResults, unit::Type{<:Dates.FixedPeriod}, lower_bound)
    totals = bin_totals(results, unit, lower_bound)
    return Dict{DateTime, Int}(bin => stats.count for (bin, stats) in totals)
end

function requests_per_unit(cache::MetricsCache, unit::Type{<:Dates.FixedPeriod}, lower_bound)
    return requests_per_unit(metrics_results(cache), unit, lower_bound)
end

"""
    avg_latency_per_unit(results::MetricsResults, unit, lower_bound)
    avg_latency_per_unit(cache::MetricsCache, unit, lower_bound)

Cached equivalent of `avg_latency_per_unit(get_history(cache.history), unit, lower_bound)`.
As with all cached time-series queries, the window edge is accurate to within
one second (see `bin_totals`).
"""
function avg_latency_per_unit(results::MetricsResults, unit::Type{<:Dates.FixedPeriod}, lower_bound)
    totals = bin_totals(results, unit, lower_bound)
    return Dict{DateTime, Number}(bin => stats.sum / stats.count for (bin, stats) in totals)
end

function avg_latency_per_unit(cache::MetricsCache, unit::Type{<:Dates.FixedPeriod}, lower_bound)
    return avg_latency_per_unit(metrics_results(cache), unit, lower_bound)
end


end
