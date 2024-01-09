module MetricsTests 
using Test
using Dates 

include("../src/Oxygen.jl")
using .Oxygen

include("../src/Metrics.jl")
using .Metrics:
    percentile, HTTPTransaction, TimeseriesRecord, get_history, push_history,
    group_transactions, get_transaction_metrics, recent_transactions,
    all_endpoint_metrics, server_metrics, error_distribution,
    prepare_timeseries_data, fill_missing_data, timeseries, series_format,
    bin_transactions, requests_per_unit, avg_latency_per_unit, clear_history

# Mock Data
const MOCK_TIMESTAMP = DateTime(2021, 1, 1, 12, 0, 0)
const MOCK_HTTP_TRANSACTION = HTTPTransaction("192.168.1.1", "/test", MOCK_TIMESTAMP, 0.5, true, 200, nothing)

# Helper Function to Create Mock Transactions
function create_mock_transactions(n::Int)
    [HTTPTransaction("192.168.1.$i", "/test/$i", MOCK_TIMESTAMP, 0.1 * i, i % 2 == 0, 200 + i, nothing) for i in 1:n]
end

# Test for push_history and get_history
@testset "History Management" begin
    clear_history()
    push_history(MOCK_HTTP_TRANSACTION)
    @test length(get_history()) == 1
    @test get_history()[1] === MOCK_HTTP_TRANSACTION
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
    transactions = recent_transactions(Minute(15))
    @test all(t -> now(UTC) - t.timestamp <= Minute(15) + Second(1), transactions)
end

# Test for all_endpoint_metrics
@testset "All Endpoint Metrics Calculation" begin
    metrics = all_endpoint_metrics()
    @test metrics isa Dict
end

# Test for server_metrics
@testset "Server Metrics Calculation" begin
    metrics = server_metrics()
    @test metrics["total_requests"] >= 0
end

# Test for error_distribution
@testset "Error Distribution Calculation" begin
    distribution = error_distribution()
    @test typeof(distribution) == Dict{String, Int}
end

# # Test for prepare_timeseries_data
# @testset "Timeseries Data Preparation" begin
#     prep_func = prepare_timeseries_data()
#     @test typeof(prep_func) == Function
# end

# Test for fill_missing_data
@testset "Fill Missing Data in Timeseries" begin
    records = [TimeseriesRecord(MOCK_TIMESTAMP, i) for i in 1:5]
    filled = fill_missing_data(records, Minute(1))
    @test length(filled) >= 5
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
    bin_transactions(Minute(15))
    req_per_unit = requests_per_unit(Minute(1))
    avg_latency = avg_latency_per_unit(Minute(1))
    @test typeof(req_per_unit) == Dict{Dates.DateTime, Int}
    @test typeof(avg_latency) == Dict{Dates.DateTime, Number}
end

# Run all tests
@testset "Metrics Module Tests" begin
    # Include all test sets here
end


end