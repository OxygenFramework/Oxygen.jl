module Metrics

using Statistics
using HTTP
using JSON3
using Profile
using Dates

include("util.jl"); using .Util
include("bodyparsers.jl"); using .BodyParsers

export MetricsMiddleware, get_history, get_history_size, 
    calculate_server_metrics,
    calculate_metrics_all_endpoints, 
    capture_metrics, dashboard

struct HTTPTransaction
    # Intristic Properties
    ip::String
    uri::String
    timestamp::DateTime

    # derived properties
    duration::Float64
    sucess::Bool
    status::Int16
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
            "percentile_latency_95th" => 0,
            "error_rate" => 0
        )
    end

    total_requests = length(transactions)
    latencies = [t.duration for t in transactions if t.duration != 0.0]
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
        "percentile_latency_95th" => percentile_95_latency,
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


function dashboard()
    html(
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>ApexCharts with Preact</title>
        <style>
            #chart {
                width: 500px;
                height: 400px;
            }
        </style>
    </head>
    <body>
        <div id="chart"></div>
        <script type="module">
            import { h, Fragment, render } from 'https://esm.sh/preact@10.19.3';
            import { useEffect, useState } from 'https://esm.sh/preact@10.19.3/hooks';
            import ApexCharts from 'https://esm.sh/apexcharts@3.45.0';
    
            function EndpointPieChart() {
                const [chartData, setChartData] = useState({ series: [], labels: [] });
    
                useEffect(() => {
                    // Fetch data
                    fetch('http://127.0.0.1:8080/docs/metrics/data')
                        .then(response => response.json())
                        .then(data => {
                            const endpointsData = data.endpoints;
                            const series = [];
                            const labels = [];
    
                            for (const endpoint in endpointsData) {
                                labels.push(endpoint);
                                series.push(endpointsData[endpoint].total_requests);
                            }
    
                            setChartData({ series, labels });
                        })
                        .catch(error => console.error('Error fetching data:', error));
                }, []);
    
                useEffect(() => {
                    // Render chart if data is available
                    if (chartData.series.length > 0 && chartData.labels.length > 0) {
                        const options = {
                            chart: {
                                type: 'pie',
                                height: '100%'
                            },
                            series: chartData.series,
                            labels: chartData.labels,
                            responsive: [{
                                breakpoint: 480,
                                options: {
                                    chart: {
                                        width: 200
                                    },
                                    legend: {
                                        position: 'bottom'
                                    }
                                }
                            }]
                        };
    
                        var chart = new ApexCharts(document.querySelector("#chart"), options);
                        chart.render();
                    }
                }, [chartData]); // Depend on chartData
    
                return h('div', null);
            }
    
    
            function Chart() {
                useEffect(() => {
                    const options = {
                        chart: {
                            type: 'bar',
                            height: '100%'
                        },
                        series: [{
                            name: 'sales',
                            data: [30, 40, 453, 50, 49, 60, 70, 91, 125]
                        }],
                        xaxis: {
                            categories: [1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999]
                        }
                    };
    
                    var chart = new ApexCharts(document.querySelector("#chart"), options);
                    chart.render();
                }, []);
    
                return h('div', null);
            }
            
    
            render(h(EndpointPieChart), document.querySelector("#chart"));
        </script>
    </body>
    </html>
    
    """
    )
end


end
