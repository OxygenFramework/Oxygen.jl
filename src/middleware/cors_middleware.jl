module CORSMiddleware

using HTTP
using ...Types

export Cors

"""
    Cors(; allowed_origins=["*"], allowed_headers=["*"], allowed_methods=["GET","POST","OPTIONS"], allow_credentials=false, max_age=nothing, extra_headers=Pair[])

Creates a middleware function that adds CORS headers to responses and handles preflight OPTIONS requests.

# Keyword Arguments

    - `allowed_origins`: Vector of allowed origins (default: ["*"]).
    - `allowed_headers`: Vector of allowed headers (default: ["*"]).
    - `allowed_methods`: Vector of allowed methods (default: ["GET","POST","OPTIONS"]).
    - `allow_credentials`: If true, adds `Access-Control-Allow-Credentials: true`.
    - `max_age`: If set, adds `Access-Control-Max-Age` header.
    - `extra_headers`: Vector of additional key-value pairs.

# Returns
A `LifecycleMiddleware` struct containing the middleware function.
"""
function Cors(; 
    allowed_origins     :: Vector{String} = ["*"], 
    allowed_headers     :: Vector{String} = ["*"], 
    allowed_methods     :: Vector{String} = ["GET","POST","OPTIONS"], 
    allow_credentials   :: Bool = false, 
    max_age             :: Union{Int,Nothing} = nothing, 
    extra_headers       :: Vector{Pair{String, String}} = Pair{String,String}[])
    
    # Helper to format header value: "*" if wildcard, else join with ", "
    format_header(xs::Vector{String}) = ("*" in xs) ? "*" : join(xs, ", ")
    
    cors_headers :: Vector{Pair{String, String}} = [
        "Access-Control-Allow-Origin" => format_header(allowed_origins),
        "Access-Control-Allow-Headers" => format_header(allowed_headers),
        "Access-Control-Allow-Methods" => format_header(allowed_methods),
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
