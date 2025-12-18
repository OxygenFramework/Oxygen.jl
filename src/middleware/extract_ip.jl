
module ExtractIPMiddleware
using HTTP
using Sockets

export ExtractIP

"""
    ExtractIP()

Middleware that extracts the client IP address from HTTP request headers and assigns it to `req.context[:ip]`.

This middleware checks common proxy headers in priority order:
1. `CF-Connecting-IP` (Cloudflare)
2. `True-Client-IP` (Akamai/Enterprise proxies)
3. `X-Forwarded-For` (standard, may be a comma-separated list; uses the first entry)
4. `X-Real-IP` (Nginx/other proxies)
5. Falls back to the pre-existing `req.context[:ip]` if no headers are present.

Intended for use before middleware that relies on accurate client IP detection, such as rate limiting or logging.
"""
function ExtractIP()
    function(handle::Function)
        function(req::HTTP.Request)
            req.context[:ip] = extract_ip(req)
            return handle(req)
        end
    end
end


"""
    extract_ip(req::HTTP.Request) :: IPAddr

Extracts the client IP address from an HTTP request, checking headers in priority order:

1. `CF-Connecting-IP` (Cloudflare)
2. `True-Client-IP` (Akamai/Enterprise proxies)
3. `X-Forwarded-For` (standard, may be a comma-separated list; uses the first entry)
4. `X-Real-IP` (Nginx/other proxies)
5. Falls back to `req.context[:ip]` if no headers are present.

Returns the parsed `IPAddr` for use in rate limiting.
"""
function extract_ip(req::HTTP.Request) :: IPAddr

    tci :: Union{String,Nothing} = nothing
    xff :: Union{String,Nothing} = nothing
    xri :: Union{String,Nothing} = nothing

    for (k, v) in req.headers
        # Case 1: Cloudflare's direct client IP header (return early since it's priority 1)
        if HTTP.Messages.field_name_isequal(k, "CF-Connecting-IP")
            return parse(IPAddr, v)
        # Case 2: Akamai/Enterprise proxies (True-Client-IP)
        elseif HTTP.Messages.field_name_isequal(k, "True-Client-IP")
            tci = v
        # Case 3: Standard X-Forwarded-For header (may be a list)
        elseif HTTP.Messages.field_name_isequal(k, "X-Forwarded-For")
            xff = v
        # Case 4: Nginx or other proxies (X-Real-IP)
        elseif HTTP.Messages.field_name_isequal(k, "X-Real-IP")
            xri = v
        end
    end

    # Case 2: Akamai/Enterprise proxies (True-Client-IP)
    if !isnothing(tci) && !isempty(tci)
        return parse(IPAddr, tci)

    # Case 3: Standard X-Forwarded-For header (may be a list)
    elseif !isnothing(xff) && !isempty(xff)
        return parse(IPAddr, strip(split(xff, ",")[1]))

     # Case 4: Nginx or other proxies (X-Real-IP)
    elseif !isnothing(xri) && !isempty(xri)
        return parse(IPAddr, xri)
    end

    # fallback to the pre-existing ip object
    return req.context[:ip]
end




end