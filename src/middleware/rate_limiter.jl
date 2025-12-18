module RateLimiterMiddleware
using HTTP
using Dates
using Sockets

# Import top level types module
using ...Types 

export RateLimiter

"""
    RateLimiter(rate_limit::Int = 100, window_period::Period = Minute(1), cleanup_period::Period = Minute(10), cleanup_threshold::Period = Minute(10))

Creates a middleware function that enforces rate limiting based on IP address, with automatic background cleanup to prevent memory leaks.

# Arguments
- `rate_limit::Int`: Maximum number of requests allowed per IP within the window period. Default is 100.
- `window_period::Period`: Time window for rate limiting. Default is 1 minute.
- `cleanup_period::Period`: Interval for running the background cleanup task. Default is 10 minutes.
- `cleanup_threshold::Period`: Minimum age of inactive IP entries before deletion during cleanup. Default is 10 minutes.

# Returns
An `LifecycleMiddleware` struct containing the middleware function and a cleanup function to stop the background task on server shutdown.
"""
function RateLimiter(;rate_limit::Int = 100, window_period::Period = Minute(1), cleanup_period::Period = Minute(10), cleanup_threshold::Period = Minute(10))

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

    function middleware(handle::Function)
        return function(req::HTTP.Request)
            try
                reset_time = 0
                should_limit = false
                remaining_requests = rate_limit

                lock(store_lock) do
                    current_time = Dates.now()
                    ip = req.context[:ip]

                    if haskey(rate_limit_store, ip)
                        count, last_reset = rate_limit_store[ip]
                        
                        # Case 2: Expired Window 
                        if current_time - last_reset > window_period
                            rate_limit_store[ip] = (1, current_time)
                            remaining_requests = rate_limit - 1
                            # Reset to current time, so reset time is full window period
                            reset_time = calculate_reset_time(current_time, current_time, window_period)

                        # Case 3: Limit Exceeded
                        elseif count >= rate_limit
                            should_limit = true
                            remaining_requests = 0
                            # Use original last_reset to calculate remaining time
                            reset_time = calculate_reset_time(current_time, last_reset, window_period)

                        # Case 4: Within Limit
                        else
                            rate_limit_store[ip] = (count + 1, last_reset)
                            remaining_requests = rate_limit - (count + 1)
                            # Calculate reset based on original last_reset
                            reset_time = calculate_reset_time(current_time, last_reset, window_period)
                        end
                    else
                        # Case 1: New IP
                        rate_limit_store[ip] = (1, current_time)
                        remaining_requests = rate_limit - 1
                        # Start from current time, full window period
                        reset_time = calculate_reset_time(current_time, current_time, window_period)
                    end
                end

                # Prepare the response
                if should_limit
                    # Create a new response for rate-limited requests
                    response = HTTP.Response(429, "Rate limit exceeded")
                    HTTP.setheader(response, "X-RateLimit-Limit" => string(rate_limit))
                    HTTP.setheader(response, "X-RateLimit-Remaining" => "0")
                    HTTP.setheader(response, "X-RateLimit-Reset" => string(reset_time))

                    return response
                else
                    # Get the response from a properly handled request
                    response = handle(req)
                    
                    # Add rate limit headers to successful responses
                    HTTP.setheader(response, "X-RateLimit-Limit" => string(rate_limit))
                    HTTP.setheader(response, "X-RateLimit-Remaining" => string(max(0, remaining_requests)))
                    HTTP.setheader(response, "X-RateLimit-Reset" => string(reset_time))
                    
                    return response
                end

            catch error
                @error "ERROR: " exception=(error, catch_backtrace())
                # Always process the incoming request even if our rate limiting fails
                return handle(req)
            end
        end
    end

    return LifecycleMiddleware(;
        middleware = middleware, 
        on_startup = on_startup,
        on_shutdown = on_shutdown
    )
end


"""
    calculate_reset_time(current_time::DateTime, last_reset::DateTime, window_period::Period) -> Int

Calculates the number of seconds remaining until the current rate limit window resets.

# Arguments
- `current_time::DateTime`: The current server time.
- `last_reset::DateTime`: The start time of the current rate limit window for the client/IP.
- `window_period::Period`: The duration of the rate limit window.

# Returns
- `Int`: The number of seconds until the rate limit window resets. Returns 0 if the window has already expired.

This value is used for the `X-RateLimit-Reset` response header, allowing clients to know when they can make new requests.
"""
function calculate_reset_time(current_time::DateTime, last_reset::DateTime, window_period::Period)
    window_end = last_reset + window_period
    seconds_remaining = ceil(Int, Dates.value(window_end - current_time) / 1000)
    return max(0, seconds_remaining)
end

end