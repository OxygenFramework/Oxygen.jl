module Metrics

using HTTP
using JSON3
using Dates
using Profile
using DataStructures
using Statistics
using RelocatableFolders

include("util.jl"); using .Util
include("bodyparsers.jl"); using .BodyParsers

export MetricsMiddleware, get_history, get_history_size, 
    calculate_server_metrics,
    calculate_metrics_all_endpoints, 
    capture_metrics, bin_and_count_transactions,
    bin_transactions, requests_per_unit, avg_latency_per_unit,
    timeseries, series_format, error_distribution

struct HTTPTransaction
    # Intristic Properties
    ip::String
    uri::String
    timestamp::DateTime

    # derived properties
    duration::Float64
    success::Bool
    status::Int16
    error_message::Union{String,Nothing}
end

global const history = Ref{CircularDeque{HTTPTransaction}}(CircularDeque{HTTPTransaction}(100_000))

function push_history(transaction::HTTPTransaction)
    pushfirst!(history[], transaction)
end

function get_history() :: Vector{HTTPTransaction}
    return collect(history[])
end

# Helper function to calculate percentile
function percentile(values, p)
    index = ceil(Int, p / 100 * length(values))
    return sort(values)[index]
end

# Function to group HTTPTransaction objects by URI prefix with a maximum depth limit
function group_transactions_by_prefix_depth_limit(transactions::Vector{HTTPTransaction}, max_depth::Int)
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
function calculate_metrics_for_transactions(transactions::Vector{HTTPTransaction})
    if isempty(transactions)
        return Dict(
            "total_requests" => 0,
            "avg_latency" => 0,
            "min_latency" => 0,
            "max_latency" => 0,
            "percentile_latency_95th" => 0,
            "error_rate" => 0
        )
    end

    total_requests = length(transactions)
    latencies = [t.duration for t in transactions if t.duration != 0.0]
    successes = [t.success for t in transactions]

    avg_latency = mean(latencies)
    min_latency = minimum(latencies)
    max_latency = maximum(latencies)
    percentile_95_latency = percentile(latencies, 95)
    total_errors = count(!, successes)
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

### Helper function to group transactions by endpoint

function recent_transactions(lower_bound=nothing) :: Vector{HTTPTransaction}
    # return everything if no window is passed
    if isnothing(lower_bound)
        return get_history()
    end
    current_time = now()
    return filter(t -> current_time - t.timestamp <= lower_bound, get_history()) 
end

function group_transactions_by_endpoint()
    grouped_transactions = Dict{String, Vector{HTTPTransaction}}()
    transactions = recent_transactions(Minute(15))
    for transaction in transactions
        push!(get!(grouped_transactions, transaction.uri, []), transaction)
    end
    return grouped_transactions
end


"""
Group transactions by URI depth with a maximum depth limit using the function
"""
function calculate_metrics_all_endpoints(lower_bound=Minute(15); max_depth=4)
    transactions = recent_transactions(lower_bound)    
    groups = group_transactions_by_prefix_depth_limit(transactions, max_depth)
    return Dict(k => calculate_metrics_for_transactions(v) for (k,v) in groups)
end


function calculate_server_metrics(lower_bound=Minute(15))
    transactions = recent_transactions(lower_bound)
    calculate_metrics_for_transactions(transactions)
end

function calculate_endpoint_metrics(endpoint_uri::String)
    endpoint_transactions = filter(t -> t.uri == endpoint_uri, get_history())
    return calculate_metrics_for_transactions(endpoint_transactions)
end

function error_distribution(lower_bound=Minute(15))
    metrics = calculate_metrics_all_endpoints(lower_bound)
    failed_counts = Dict{String, Int}()
    for (group_prefix, transaction_metrics) in metrics
        failures = transaction_metrics["total_errors"]
        if failures > 0
            failed_counts[group_prefix] = get(failed_counts, group_prefix, 0) + failures
        end
    end
    return failed_counts
end


struct TimeseriesRecord 
    timestamp::DateTime
    value::Number
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
function bin_transactions(lower_bound=Minute(15), unit=Minute, strategy=nothing) :: Dict{DateTime,Vector{HTTPTransaction}}
    transactions = recent_transactions(lower_bound)
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

function requests_per_unit(unit, lower_bound=Minute(15))
    bin_counts = Dict{DateTime, Int}()
    function count_transactions(bin, transaction) 
        bin_counts[bin] = get(bin_counts, bin, 0) + 1
    end
    bin_transactions(lower_bound, unit, count_transactions)
    return bin_counts
end

"""
Return the average latency per minute for the server
"""
function avg_latency_per_unit(unit, lower_bound=Minute(15))
    bin_counts = Dict{DateTime, Vector{Number}}()
    function strategy(bin, transaction) 
        if haskey(bin_counts, bin)
            push!(bin_counts[bin], transaction.duration)
        else 
            bin_counts[bin] = [transaction.duration]
        end
    end
    bin_transactions(lower_bound, unit, strategy)
    averages = Dict{DateTime, Number}()
    for (k,v) in bin_counts
        averages[k] = mean(v)
    end
    return averages
end



### Middleware

function MetricsMiddleware(catch_errors::Bool)
    return function(handler)
        return function(req::HTTP.Request)
            return handlerequest(catch_errors) do 
                start_time = time()
                try
                    # Handle the request
                    response = handler(req)

                    # Log response time
                    response_time = time() - start_time

                    if response.status == 200
                        push_history(HTTPTransaction(
                            string(req.context[:ip]),
                            string(req.target),
                            now(UTC),
                            response_time,
                            true,
                            response.status,
                            nothing
                        ))
                    else 
                        push_history(HTTPTransaction(
                            string(req.context[:ip]),
                            string(req.target),
                            now(UTC),
                            response_time,
                            false,
                            response.status,
                            text(response)
                        ))
                    end

                    # Return the response
                    return response
                catch e
                    response_time = time() - start_time

                    # Log the error
                    push_history(HTTPTransaction(
                        string(req.context[:ip]),
                        string(req.target),
                        now(UTC),
                        response_time,
                        false,
                        response.status,
                        string(typeof(e))
                    ))

                    # let our caller figure out if they want to handle the error or not
                    rethrow(e)
                end
            end
        end
    end
end

end
