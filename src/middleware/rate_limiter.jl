module RateLimiterMiddleware
using HTTP
using Dates
using Sockets

# Import top level types module
using ...Types 
using ..ExtractIPMiddleware: ExtractIP

export RateLimiter, set_rate_header, calculate_reset_time

"""
    RateLimiter(; rate_limit::Int = 100, window::Period = Minute(1), cleanup_period::Period = Minute(10), cleanup_threshold::Period = Minute(10), auto_extract_ip::Bool = true)

Creates a middleware function that enforces rate limiting based on IP address, with automatic background cleanup to prevent memory leaks.

# Arguments
- `rate_limit::Int`: Maximum number of requests allowed per IP within the window period. Default is 100.
- `window::Period`: Time window for rate limiting. Default is 1 minute.
- `cleanup_period::Period`: Interval for running the background cleanup task. Default is 10 minutes.
- `cleanup_threshold::Period`: Minimum age of inactive IP entries before deletion during cleanup. Default is 10 minutes.
- `auto_extract_ip::Bool`: If `true` (default), the middleware will automatically extract the client IP address from the request using the built-in extractor.

# Customization
To customize IP extraction, set `auto_extract_ip=false` and insert your own middleware before the rate limiter to assign the desired IP address to `req.context[:ip]`. This is useful for advanced scenarios such as extracting IPs from custom headers, authentication tokens, or supporting non-standard proxy setups.
```

# Returns
An `LifecycleMiddleware` struct containing the middleware function and a cleanup function to stop the background task on server shutdown.
"""
function RateLimiter(;
    rate_limit::Int = 100, 
    window::Period = Minute(1), 
    cleanup_period::Period = Minute(10), 
    cleanup_threshold::Period = Minute(10),
    auto_extract_ip::Bool = true,
    exempt_paths::Vector{String} = String[])

    rate_limit_store = Dict{IPAddr, Tuple{Int, DateTime}}()
    store_lock = ReentrantLock()
    
    running = Ref{Bool}(false)
    cleanup_task = Ref{Union{Task,Nothing}}(nothing)

    function on_startup()
        # enable the flag
        running[] = true

        # prevent multiple cleanup tasks from being started
        if isnothing(cleanup_task[])
            # Start Background cleanup task
            cleanup_task[] = @async while running[]
                sleep(cleanup_period)
                lock(store_lock) do
                    current_time = now()
                    to_delete = []
                    for (ip, (_, last_reset)) in rate_limit_store
                        if current_time - last_reset > cleanup_threshold
                            push!(to_delete, ip)
                        end
                    end
                    for ip in to_delete
                        delete!(rate_limit_store, ip)
                    end
                end
            end
        end
    end

    # Stop function to halt the task
    function on_shutdown()
        running[] = false
        cleanup_task[] = nothing
    end

    function rate_limit_only(handle::Function)
        return function(req::HTTP.Request)
            try

                # allow passthrough for exempt paths
                for ex in exempt_paths
                    if startswith(req.target, ex)
                        return handle(req)
                    end
                end
                        
                reset_time = 0
                should_limit = false
                remaining_requests = rate_limit

                lock(store_lock) do
                    current_time = Dates.now()
                    ip = req.context[:ip]

                    if haskey(rate_limit_store, ip)
                        count, last_reset = rate_limit_store[ip]

                        # Case 2: Expired Window 
                        if current_time - last_reset > window
                            rate_limit_store[ip] = (1, current_time)
                            remaining_requests = rate_limit - 1
                            # Reset to current time, so reset time is full window period
                            reset_time = calculate_reset_time(current_time, current_time, window)

                        # Case 3: Limit Exceeded
                        elseif count >= rate_limit
                            should_limit = true
                            remaining_requests = 0
                            # Use original last_reset to calculate remaining time
                            reset_time = calculate_reset_time(current_time, last_reset, window)

                        # Case 4: Within Limit
                        else
                            rate_limit_store[ip] = (count + 1, last_reset)
                            remaining_requests = rate_limit - (count + 1)
                            # Calculate reset based on original last_reset
                            reset_time = calculate_reset_time(current_time, last_reset, window)
                        end
                    else
                        # Case 1: New IP
                        rate_limit_store[ip] = (1, current_time)
                        remaining_requests = rate_limit - 1
                        # Start from current time, full window period
                        reset_time = calculate_reset_time(current_time, current_time, window)
                    end
                end

                # Prepare the response
                if should_limit
                    # Create a new response for rate-limited requests
                    response = HTTP.Response(429, "Rate limit exceeded")
                    set_rate_headers!(response, rate_limit, 0, reset_time)
                    return response
                else
                    # Get the response from a properly handled request
                    response = handle(req)
                    # Add rate limit headers to successful responses
                    set_rate_headers!(response, rate_limit, remaining_requests, reset_time)
                    return response
                end

            catch error
                @error "ERROR: " exception=(error, catch_backtrace())
                # Always process the incoming request even if our rate limiting fails
                return handle(req)
            end
        end
    end

    # If auto_extract_ip is true, then we'll use this composed version of the middleware
    function extract_ip_and_rate_limit(handle::Function) :: Function
        reduce(|>, [handle, rate_limit_only, ExtractIP()])
    end

    return LifecycleMiddleware(;
        middleware = auto_extract_ip ? extract_ip_and_rate_limit : rate_limit_only, 
        on_startup = on_startup,
        on_shutdown = on_shutdown
    )
end


"""
    calculate_reset_time(current_time::DateTime, last_reset::DateTime, window::Period) -> Int

Calculates the number of seconds remaining until the current rate limit window resets.

# Arguments
- `current_time::DateTime`: The current server time.
- `last_reset::DateTime`: The start time of the current rate limit window for the client/IP.
- `window::Period`: The duration of the rate limit window.

# Returns
- `Int`: The number of seconds until the rate limit window resets. Returns 0 if the window has already expired.

This value is used for the `X-RateLimit-Reset` response header, allowing clients to know when they can make new requests.
"""
function calculate_reset_time(current_time::DateTime, last_reset::DateTime, window::Period)
    window_end = last_reset + window
    seconds_remaining = ceil(Int, Dates.value(window_end - current_time) / 1000)
    return max(0, seconds_remaining)
end


"""
    set_rate_headers!(resp::HTTP.Response, rate_limit::Int, remaining_requests::Int, reset_time::Int)

Conditionally sets standard rate limiting headers on an HTTP response if they are not already present.
This function implements a "header preservation" pattern, ensuring that headers set by inner middleware
(e.g., route-level rate limits) are not overwritten by outer middleware (e.g., router-level limits),
allowing the most restrictive or specific limits to take precedence in nested middleware chains.

# Arguments
- `resp::HTTP.Response`: The HTTP response object to modify. Headers are added in-place.
- `rate_limit::Int`: The maximum number of requests allowed in the current window. Used for the `X-RateLimit-Limit` header.
- `remaining_requests::Int`: The number of requests remaining in the current window. Used for the `X-RateLimit-Remaining` header (clamped to 0 if negative).
- `reset_time::Int`: The number of seconds until the rate limit window resets. Used for the `X-RateLimit-Reset` header.
"""
function set_rate_headers!(resp::HTTP.Response, rate_limit::Int, remaining_requests::Int, reset_time::Int)
    
    # Header flags which are set to true when they're found
    has_limit = false
    has_remaining = false
    has_reset = false
    has_retry = false
    
    # Loop over the headers once and try to find each header
    for (k, v) in resp.headers
        if !has_retry && HTTP.Messages.field_name_isequal(k, "Retry-After")
            has_retry = true
        elseif !has_limit && HTTP.Messages.field_name_isequal(k, "X-RateLimit-Limit")
            has_limit = true
        elseif !has_remaining && HTTP.Messages.field_name_isequal(k, "X-RateLimit-Remaining" )
            has_remaining = true
        elseif !has_reset && HTTP.Messages.field_name_isequal(k, "X-RateLimit-Reset")
            has_reset = true
        end
    end

    # Conditionally set the headers if they don't exist
    if !has_retry
        HTTP.setheader(resp, "Retry-After" => string(reset_time))
    end
    if !has_limit
        HTTP.setheader(resp, "X-RateLimit-Limit" => string(rate_limit))
    end
    if !has_remaining
        HTTP.setheader(resp, "X-RateLimit-Remaining" => string(max(0, remaining_requests)))
    end
    if !has_reset
        HTTP.setheader(resp, "X-RateLimit-Reset" => string(reset_time))
    end  

end

end