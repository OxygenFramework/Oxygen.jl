module Metrics

using Statistics
using HTTP
using JSON3
using Profile
using Dates

include("util.jl"); using .Util

export MetricsMiddleware, get_history, get_history_size, 
    calculate_server_metrics,
    calculate_metrics_all_endpoints

struct HTTPTransaction
    # Intristic Properties
    ip::String
    uri::String
    timestamp::DateTime

    # derived properties
    duration::Float64
    sucess::Bool
    error_message::Union{String,Nothing}
end
    
global const history_size = Ref{Int}(0)
global const history = Ref{Vector{HTTPTransaction}}([])

function push_history(transaction::HTTPTransaction)
    history_size[] += 1
    push!(history[], transaction)
end

### Individual global constants for each metric

global const endpoints_hits = Ref{Dict{String, Int}}(Dict())
global const ip_hits = Ref{Dict{String, Int}}(Dict())
global const total_requests = Ref{Int}(0)
global const unique_clients = Ref{Set{String}}(Set())
global const error_rate = Ref{Dict{String, Dict{String, Int}}}(Dict())
global const resource_usage = Ref{Any}(Dict())

### New variables for response time calculation
global cumulative_response_time = Ref{Float64}(0.0)
global response_count = Ref{Int}(0)

function get_history_size() :: Int
    return copy(history_size[])
end

function get_history() :: Vector{HTTPTransaction}
    return copy(history[])
end


# Helper function to calculate percentile
function percentile(values, p)
    index = ceil(Int, p / 100 * length(values))
    return sort(values)[index]
end

### Helper function to calculate metrics for a set of transactions
function calculate_metrics_for_transactions(transactions::Vector{HTTPTransaction})
    if isempty(transactions)
        return Dict(
            "total_requests" => 0,
            "avg_latency" => 0,
            "min_latency" => 0,
            "max_latency" => 0,
            "95th_percentile_latency" => 0,
            "error_rate" => 0
        )
    end

    total_requests = length(transactions)
    latencies = [t.duration for t in transactions]
    successes = [t.sucess for t in transactions]

    avg_latency = mean(latencies)
    min_latency = minimum(latencies)
    max_latency = maximum(latencies)
    percentile_95_latency = percentile(latencies, 95)
    total_errors = count(!, successes)
    error_rate = total_errors / total_requests

    return Dict(
        "total_requests" => total_requests,
        "avg_latency" => avg_latency,
        "min_latency" => min_latency,
        "max_latency" => max_latency,
        "95th_percentile_latency" => percentile_95_latency,
        "error_rate" => error_rate
    )
end

### Helper function to group transactions by endpoint
function group_transactions_by_endpoint()
    grouped_transactions = Dict{String, Vector{HTTPTransaction}}()
    for transaction in history[]
        push!(get!(grouped_transactions, transaction.uri, []), transaction)
    end
    return grouped_transactions
end

function calculate_server_metrics()
    calculate_metrics_for_transactions(history[])
end

function calculate_endpoint_metrics(endpoint_uri::String)
    endpoint_transactions = filter(t -> t.uri == endpoint_uri, history[])
    return calculate_metrics_for_transactions(endpoint_transactions)
end

function calculate_metrics_all_endpoints()
    grouped_transactions = group_transactions_by_endpoint()
    endpoint_metrics = Dict{String, Dict}()
    for (uri, transactions) in grouped_transactions
        endpoint_metrics[uri] = calculate_metrics_for_transactions(transactions)
    end
    return endpoint_metrics
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

                    push_history(HTTPTransaction(
                        string(req.context[:ip]),
                        string(req.target),
                        now(UTC),
                        response_time,
                        true,
                        nothing
                    ))

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
