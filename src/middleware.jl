module Middleware

using HTTP

export compose, genkey

"""
This function is used to generate dictionary keys which lookup middleware for routes
"""
function genkey(httpmethod::String, path::String)::String
    return "$httpmethod|$path"
end

"""
This function is used to build up the middleware chain for all our endpoints
"""
function buildmiddleware(key::String, handler::Function, globalmiddleware::Vector, custommiddleware::Dict) :: Function

    # lookup the middleware for this path
    routermiddleware, routemiddleware = get(custommiddleware, key, (nothing, nothing))

    # sanitize outputs (either value can be nothing)
    routermiddleware = isnothing(routermiddleware) ? [] : routermiddleware
    routemiddleware = isnothing(routemiddleware) ? [] : routemiddleware

    # initialize our middleware layers
    layers::Vector{Function} = [handler]

    # append the middleware in reverse order (so when we reduce over it, it's in the correct order)
    append!(layers, routemiddleware)
    append!(layers, routermiddleware)
    append!(layers, globalmiddleware)

    # combine all the middleware functions together
    return reduce(|>, layers)
end

"""
This function dynamically determines which middleware functions to apply to a request at runtime. 
If router or route specific middleware is defined, then it's used instead of the globally defined
middleware. 
"""
function compose(router::HTTP.Router, cache_lock::ReentrantLock, globalmiddleware::Vector, custommiddleware::Dict, middleware_cache::Dict)
    return function (handler)
        return function (req::HTTP.Request)

            innerhandler, path, _ = HTTP.Handlers.gethandler(router, req)

            # Check if the current request matches one of our predefined routes 
            if innerhandler !== nothing

                # Check if we already have a cached middleware function for this specific route
                key = genkey(req.method, path)
                func = get(middleware_cache, key, nothing)
                if !isnothing(func)
                    return func(req)
                end

                # Combine all the middleware functions together 
                strategy = buildmiddleware(key, handler, globalmiddleware, custommiddleware)
                
                ## Below Double-checked locking to reduce the overhead of acquiring a lock
                # Check if the middleware function is in the cache before locking.
                if !haskey(middleware_cache, key)
                    # Lock to ensure only one thread adds to the cache.
                    lock(cache_lock) do 
                        # Double-check if the function is still not in the cache.
                        if !haskey(middleware_cache, key)
                            # Add the function to the cache.
                            middleware_cache[key] = strategy
                        end
                    end
                end
                
                return strategy(req)
            end
    
            return handler(req)
        end
    end
end

end