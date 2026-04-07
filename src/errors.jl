module Errors
## In this module, we export commonly used exceptions across the package 

export ValidationError, CookieError

# This is used by the Extractors.jl module to signal that a validation error has occurred
struct ValidationError <: Exception
    msg::String
    cause::Union{Nothing, Exception}
    ValidationError(msg::String) = new(msg, nothing)
    ValidationError(msg::String, cause::Exception) = new(msg, cause)
end

function Base.showerror(io::IO, e::ValidationError)
    print(io, "Validation Error: $(e.msg)")
    if !isnothing(e.cause)
        print(io, "\nCaused by: ")
        showerror(io, e.cause)
    end
end

struct CookieError <: Exception
    msg::String
end

function Base.showerror(io::IO, e::CookieError)
    print(io, "Cookie Error: $(e.msg)")
end

end