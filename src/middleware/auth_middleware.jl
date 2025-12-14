module AuthMiddleware

using HTTP
using ...Types

export BearerAuth

const INVALID_HEADER = HTTP.Response(401, "Unauthorized: Missing or invalid Authorization header")
const EXPIRED_TOKEN = HTTP.Response(401, "Unauthorized: Invalid or expired token")

"""
    BearerAuth(validate_token::Function; header::String = "Authorization", scheme::String = "Bearer")

Creates a middleware function for authentication using a pluggable token validation function.

# Arguments
- `validate_token::Function`: A function that takes a token string and returns user info (or `nothing` if invalid).
- `header::String = "Authorization"`: The name of the header to check for the token.
- `scheme::String = "Bearer"`: The authentication scheme prefix in the header (e.g., "Bearer" for "Bearer <token>").

# Returns
A `LifecycleMiddleware` struct containing the middleware function and a no-op shutdown function.
"""
function BearerAuth(validate_token::Function; header::String = "Authorization", scheme::String = "Bearer")

    full_scheme = scheme * " "
    scheme_prefix_len = length(full_scheme)

    return function (handle::Function)
        return function(req::HTTP.Request)

            # Try to extract the auth header
            auth_header = HTTP.header(req, header, missing)
            if ismissing(auth_header) || !startswith(auth_header, full_scheme)
                return INVALID_HEADER
            end

            header_len = length(auth_header)

            # Ensure there is something after the scheme (e.g. "Bearer <token>")
            if header_len <= scheme_prefix_len
                return INVALID_HEADER
            end
            
            # zero-copy view of the token portion
            token = strip(SubString(auth_header, scheme_prefix_len+1:header_len))
            if isempty(token)
                return INVALID_HEADER
            end

            # Validate or Reject incoming request
            user_info = validate_token(token)
            if user_info === nothing || user_info === missing
                return EXPIRED_TOKEN
            else
                req.context[:user] = user_info
                return handle(req)
            end
        end
    end
end

end
