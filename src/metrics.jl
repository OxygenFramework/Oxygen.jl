module Metrics

using HTTP
using JSON3
using Dates
using DataStructures
using Statistics
using RelocatableFolders

include("util.jl"); using .Util
include("bodyparsers.jl"); using .BodyParsers

export MetricsMiddleware, get_history, clear_history, push_history, 
    HTTPTransaction,
    server_metrics,
    all_endpoint_metrics, 
    capture_metrics, bin_and_count_transactions,
    bin_transactions, requests_per_unit, avg_latency_per_unit,
    timeseries, series_format, error_distribution,
    prepare_timeseries_data

struct TimeseriesRecord 
    timestamp::DateTime
    value::Number
end

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

global const history = Ref{CircularDeque{HTTPTransaction}}(CircularDeque{HTTPTransaction}(1_000_000))


function push_history(transaction::HTTPTransaction)
    pushfirst!(history[], transaction)
end

function get_history() :: Vector{HTTPTransaction}
    return collect(history[])
end

function clear_history()
    empty!(history[])
end

# Helper function to calculate percentile
function percentile(values, p)
    index = ceil(Int, p / 100 * length(values))
    return sort(values)[index]
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

function recent_transactions(::Nothing) :: Vector{HTTPTransaction}
    return get_history()
end

function recent_transactions(lower_bound::Dates.Period) :: Vector{HTTPTransaction}
    current_time = now(UTC)
    adjusted = lower_bound + Second(1)
    return filter(t -> current_time - t.timestamp <= adjusted, get_history()) 
end

# Needs coverage
function recent_transactions(lower_bound::Dates.DateTime) :: Vector{HTTPTransaction}
    adjusted = lower_bound + Second(1)
    return filter(t -> t.timestamp >= adjusted, get_history()) 
end

"""
Group transactions by URI depth with a maximum depth limit using the function
"""
function all_endpoint_metrics(lower_bound=Minute(15); max_depth=4)
    transactions = recent_transactions(lower_bound)    
    groups = group_transactions(transactions, max_depth)
    return Dict(k => get_transaction_metrics(v) for (k,v) in groups)
end


function server_metrics(lower_bound=Minute(15))
    transactions = recent_transactions(lower_bound)
    get_transaction_metrics(transactions)
end

# Needs coverage
function endpoint_metrics(endpoint_uri::String)
    endpoint_transactions = filter(t -> t.uri == endpoint_uri, get_history())
    return get_transaction_metrics(endpoint_transactions)
end

function error_distribution(lower_bound=Minute(15))
    metrics = all_endpoint_metrics(lower_bound)
    failed_counts = Dict{String, Int}()
    for (group_prefix, transaction_metrics) in metrics
        failures = transaction_metrics["total_errors"]
        if failures > 0
            failed_counts[group_prefix] = get(failed_counts, group_prefix, 0) + failures
        end
    end
    return failed_counts
end

# """
# Helper function used to convert internal data so that it can be viewd by a graph more easily
# """
# function prepare_timeseries_data(unit::Dates.TimePeriod=Second(1))
#     function(binned_records::Dict)
#         binned_records |> timeseries |> fill_missing_data(unit, fill_to_current=true, sort=false) |> series_format
#     end
# end

function prepare_timeseries_data()
    function(binned_records::Dict)
        binned_records |> timeseries |> series_format
    end
end

# function fill_missing_data(unit::Dates.TimePeriod=Second(1); fill_to_current::Bool=false, sort::Bool=true)
#     return function(records::Vector{TimeseriesRecord})
#         return fill_missing_data(records, unit, fill_to_current=fill_to_current, sort=sort)
#     end
# end

# function fill_missing_data(records::Vector{TimeseriesRecord}, unit::Dates.TimePeriod=Second(1); fill_to_current::Bool=false, sort::Bool=true)
#     # Ensure the input is sorted by timestamp
#     if sort 
#         sort!(records, by = x -> x.timestamp)
#     end

#     filled_records = Vector{TimeseriesRecord}()
#     last_record_time = nothing  # Initialize variable to store the time of the last record

#     for i in 1:length(records)
#         # Add the current record to the filled_records
#         push!(filled_records, records[i])
#         last_record_time = records[i].timestamp  # Update the time of the last record

#         # If this is not the last record, check the gap to the next record
#         if i < length(records)
#             next_time = records[i+1].timestamp
#             while last_record_time + unit < next_time
#                 last_record_time += unit
#                 push!(filled_records, TimeseriesRecord(last_record_time, 0))
#             end
#         end
#     end

#     # If fill_to_current is true, fill in the gap between the last record and the current time
#     if fill_to_current && !isnothing(last_record_time)
#         current_time = now(UTC)
#         while last_record_time + unit < current_time
#             last_record_time += unit
#             push!(filled_records, TimeseriesRecord(last_record_time, 0))
#         end
#     end

#     return filled_records
# end


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



end
