module RateLimiterLRUMiddleware

using HTTP
using Dates
using Sockets
using LRUCache

using ...Types 
using ..ExtractIPMiddleware: ExtractIP
using ..RateLimiterMiddleware: set_rate_headers!, calculate_reset_time

export RateLimiterLRU

"""
    RateLimiterLRU(; rate_limit::Int=100, window::Period=Minute(1), max_clients::Int=10000, exempt_paths::Vector{String}=String[], auto_extract_ip::Bool=true)

Creates a middleware function that enforces rate limiting using an LRU cache for sliding window tracking.
This implementation provides true sliding window behavior where each request creates its own expiration time,
offering more precise rate limiting than fixed windows but with higher memory usage.

# Arguments
- `rate_limit::Int`: Maximum requests per client per window. Default 100.
- `window::Period`: Sliding time window duration. Default 1 minute.
- `max_clients::Int`: Maximum distinct client buckets in LRU cache. Default 10000.
- `exempt_paths::Vector{String}`: Request path prefixes to skip rate limiting. Default empty.
- `auto_extract_ip::Bool`: If true, automatically extract IP address from request. Default true.

# Algorithm
Uses a sliding window approach where:
1. Each request timestamp is stored individually
2. On each request, expired timestamps are pruned
3. Current request count is checked against limit
4. LRU eviction prevents unbounded memory growth

# Returns
A middleware function with signature: `handle -> req -> response`
"""
function RateLimiterLRU(;
    rate_limit::Int = 100,
    window::Period = Minute(1),
    max_clients::Int = 10000,
    exempt_paths::Vector{String} = String[],
    auto_extract_ip::Bool = true)

    # LRU cache: IPAddr -> Vector of request timestamps
    rate_limit_store = LRU{IPAddr, Vector{DateTime}}(maxsize = max_clients)
    store_lock = ReentrantLock()
    
    # Precompute fallback reset seconds (window in milliseconds → seconds)
    default_reset_seconds = Int(ceil(Dates.value(window) / 1000))

    # Compute reset time from timestamps (safe for empty vectors)
    function compute_reset_time_safe(current_time::DateTime, timestamps::Vector{DateTime})
        if isempty(timestamps)
            return default_reset_seconds
        else
            oldest_timestamp = minimum(timestamps)
            return calculate_reset_time(current_time, oldest_timestamp, window)
        end
    end

    function rate_limit_only(handle::Function)
        return function(req::HTTP.Request)
            try
                # Check exempt paths first (most efficient early return)
                for exempt_path in exempt_paths
                    if startswith(req.target, exempt_path)
                        return handle(req)
                    end
                end

                current_time = Dates.now()
                ip = req.context[:ip]
                
                lock(store_lock) do
                    # Get existing timestamps or create empty vector
                    timestamps = get!(rate_limit_store, ip, DateTime[])

                    # Prune expired timestamps (sliding window cleanup)
                    # Keep only timestamps within the current window
                    cutoff_time = current_time - window
                    filter!(timestamp -> timestamp > cutoff_time, timestamps)

                    # Check if adding this request would exceed the limit
                    if length(timestamps) >= rate_limit
                        # Rate limit exceeded - calculate when client can retry
                        # The reset time should be when the oldest request in the window expires
                        reset_time = compute_reset_time_safe(current_time, timestamps)
                        
                        resp = HTTP.Response(429, "429 Too Many Requests")
                        set_rate_headers!(resp, rate_limit, 0, reset_time)
                        return resp
                    else
                        # Within limit - record this request
                        push!(timestamps, current_time)
                        # Update the LRU cache with modified vector
                        rate_limit_store[ip] = timestamps

                        # Process the request
                        response = handle(req)

                        # Calculate remaining requests and reset time for headers
                        remaining_requests = rate_limit - length(timestamps)
                        
                        # For sliding window: reset time is when the oldest request expires
                        reset_time = compute_reset_time_safe(current_time, timestamps)
                        
                        set_rate_headers!(response, rate_limit, remaining_requests, reset_time)
                        return response
                    end
                end
                
            catch error
                @error "Rate limiter LRU error" exception=(error, catch_backtrace())
                # Always proceed on middleware errors to maintain service availability
                return handle(req)
            end
        end
    end

    # Compose with IP extraction if auto_extract_ip is enabled
    function extract_ip_and_rate_limit(handle::Function)
        return reduce(|>, [handle, rate_limit_only, ExtractIP()])
    end

    return auto_extract_ip ? extract_ip_and_rate_limit : rate_limit_only
end

end