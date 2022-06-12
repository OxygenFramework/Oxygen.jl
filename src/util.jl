module Util 

export method_argnames

# https://discourse.julialang.org/t/get-the-argument-names-of-an-function/32902/4
function method_argnames(m::Method)
    argnames = ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), m.slot_syms)
    isempty(argnames) && return argnames
    return argnames[1:m.nargs]
end

end