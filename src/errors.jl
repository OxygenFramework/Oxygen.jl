module Errors
## In this module, we export commonly used exceptions across the package 

export ValidationError

# This is used by the Extractors.jl module to signal that a validation error has occurred
struct ValidationError <: Exception
    msg::String
end

function Base.showerror(io::IO, e::ValidationError)
    print(io, "Validation Error: $(e.msg)")
end

end