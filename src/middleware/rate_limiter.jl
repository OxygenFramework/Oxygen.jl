module RateLimiterMiddleware
using HTTP
using Dates
using Sockets

# Import top level types module
using ...Types 

export RateLimiter, rate_limiter

const EXCEEDED_RESPONSE = HTTP.Response(429, "Rate limit exceeded")

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
                should_limit = false
                lock(store_lock) do
                    current_time = Dates.now()
                    ip = req.context[:ip]

                    if haskey(rate_limit_store, ip)
                        count, last_reset = rate_limit_store[ip]
                        
                        # case 2: known Ip and expired window (reset the count)
                        if current_time - last_reset > window_period
                            rate_limit_store[ip] = (1, current_time)

                        # case 3: Ip seen, window active, and limit is exceeded
                        elseif count >= rate_limit
                            should_limit = true
                        
                        # case 4: IP seen, window active, and limit not exceeded
                        else
                            rate_limit_store[ip] = (count + 1, last_reset)
                        end
                    else
                        # case 1: unknown ip - start counting
                        rate_limit_store[ip] = (1, current_time)
                    end
                end

                if should_limit
                    return EXCEEDED_RESPONSE
                else
                    return handle(req)
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


# lowercase alias for more julia-like naming
const rate_limiter = RateLimiter

end