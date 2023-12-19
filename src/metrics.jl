module Metrics

using DataStructures
using Statistics
using HTTP
using JSON3
using Profile
using Dates

# include("util.jl"); using .Util

export MetricsMiddleware, get_endpoints_hits, get_ip_hits, 
    get_total_requests, get_unique_clients, get_error_rate, get_resource_usage,
    calculate_error_rate, average_response_time, get_history, handlerequest

global const history = Ref{CircularDeque{HTTP.Request}}(CircularDeque{HTTP.Request}(10_000))

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

function get_history()
    return history[]
end

### Getter functions
function get_endpoints_hits()
    return copy(endpoints_hits[])
end

function get_ip_hits()
    return copy(ip_hits[])
end

function get_total_requests()
    return copy(total_requests[])
end

function get_unique_clients()
    return copy(unique_clients[])
end

function get_error_rate()
    return copy(error_rate[])
end

function get_resource_usage()
    return copy(resource_usage[])
end


### Metric Functions

function log_endpoint_hit(endpoint::String)
    endpoints_hits[][endpoint] = get(endpoints_hits[], endpoint, 0) + 1
end

function log_ip_hit(ip::String)
    ip_hits[][ip] = get(ip_hits[], ip, 0) + 1
    push!(unique_clients[], ip)
end

function log_response_time(time::Float64)
    push!(response_times[], time)
end

function update_request_count()
    total_requests[] += 1
end

function log_error(endpoint::String, error_type::String)
    if !haskey(error_rate[], endpoint)
        error_rate[][endpoint] = Dict()
    end
    error_rate[][endpoint][error_type] = get(error_rate[][endpoint], error_type, 0) + 1
end


function log_response_time(time::Float64)
    cumulative_response_time[] += time
    response_count[] += 1
end

function average_response_time()
    return response_count[] > 0 ? cumulative_response_time[] / response_count[] : 0.0
end

function calculate_error_rate()
    total_requests = sum(values(endpoints_hits[]))
    total_errors = sum([sum(values(ep_errors)) for ep_errors in values(error_rate[])])
    return total_requests > 0 ? total_errors / total_requests : 0.0
end

function reset_metrics()
    endpoints_hits[] = Dict()
    ip_hits[] = Dict()
    total_requests[] = 0
    unique_clients[] = Set()
    error_rate[] = Dict()
    resource_usage[] = Dict()
    cumulative_response_time[] = 0.0
    response_count[] = 0
end

struct HTTPTransaction
    # Intristic Properties
    ip::String
    uri::String
    start::DateTime
    request::HTTP.Request
    response::HTTP.Response

    # derived properties
    duration::Float64
    error::Bool
    error_message::String
end

function handlerequest(getresponse::Function, catch_errors::Bool) :: HTTP.Response
    if !catch_errors
        return getresponse()
    else 
        try 
            return getresponse()       
        catch error
            @error "ERROR: " exception=(error, catch_backtrace())
            return HTTP.Response(500, "The Server encountered a problem")
        end  
    end
end


### Middleware

function MetricsMiddleware(catch_errors::Bool)
    return function(handler)
        return function(req::HTTP.Request)
            return handlerequest(catch_errors) do 
                push!(history[], req)

                println(now(UTC))

                start_time = time()
                # Update metrics for request
                log_endpoint_hit(string(req.target))
                log_ip_hit(string(req.context[:ip]))
                update_request_count()

                try
                    # Handle the request
                    response = handler(req)
    
                    # Log response time
                    response_time = time() - start_time
                    log_response_time(response_time)

                    # Return the response
                    return response
                catch e
                    # Log the error
                    log_error(string(req.target), string(typeof(e)))

                    # let our caller figure out if they want to handle the error or not
                    rethrow(e)
                end
            end
        end
    end
end


end # module
