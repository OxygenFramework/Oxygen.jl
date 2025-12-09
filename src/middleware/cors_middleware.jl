module CORSMiddleware

using HTTP
using ...Types

export Cors

"""
    Cors(; allowed_origins="*", allowed_headers="*", allowed_methods="GET, POST, OPTIONS", allow_credentials=false, max_age=nothing, cors_headers...)

Creates a middleware function that adds CORS headers to responses and handles preflight OPTIONS requests.

# Keyword Arguments

    - `allowed_origins`: Value for `Access-Control-Allow-Origin` (default: "*").
    - `allowed_headers`: Value for `Access-Control-Allow-Headers` (default: "*").
    - `allowed_methods`: Value for `Access-Control-Allow-Methods` (default: "GET, POST, OPTIONS").
    - `allow_credentials`: If true, adds `Access-Control-Allow-Credentials: true`.
    - `max_age`: If set, adds `Access-Control-Max-Age` header.
        - `extra_headers`: Vector of additional key-value pairs (e.g. `["Access-Control-Expose-Headers" => "X-My-Header", "X-Test-Header" => "TestValue"]`) to be added as extra CORS headers.

# Returns
A `LifecycleMiddleware` struct containing the middleware function.
"""
function Cors(; allowed_origins="*", allowed_headers="*", allowed_methods="GET,POST,OPTIONS", allow_credentials=false, max_age=nothing, extra_headers=Pair[])
    cors_headers = [
        "Access-Control-Allow-Origin" => allowed_origins,
        "Access-Control-Allow-Headers" => allowed_headers,
        "Access-Control-Allow-Methods" => allowed_methods,
    ]
    append!(cors_headers, extra_headers)

    if allow_credentials
        push!(cors_headers, "Access-Control-Allow-Credentials" => "true")
    end

    if max_age !== nothing
        push!(cors_headers, "Access-Control-Max-Age" => string(max_age))
    end

    return function(handle::Function)
        return function(req::HTTP.Request)
            if HTTP.method(req) == "OPTIONS"
                return HTTP.Response(200, cors_headers)
            else
                response = handle(req)
                append!(response.headers, cors_headers)
                return response
            end
        end
    end
end

end
