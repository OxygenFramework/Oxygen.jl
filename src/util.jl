module Util 
using HTTP 

export method_argnames, recursive_merge, queryparams, html, redirect

# https://discourse.julialang.org/t/get-the-argument-names-of-an-function/32902/4
function method_argnames(m::Method)
    argnames = ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), m.slot_syms)
    isempty(argnames) && return argnames
    return argnames[1:m.nargs]
end

# https://discourse.julialang.org/t/multi-layer-dict-merge/27261/7
recursive_merge(x::AbstractDict...) = merge(recursive_merge, x...)
recursive_merge(x::AbstractVector...) = cat(x...; dims=1)
recursive_merge(x...) = x[end]


### Request helper functions ###

"""
    queryparams(request::HTTP.Request)

Parse's the query parameters from the Requests URL and return them as a Dict
"""
function queryparams(req::HTTP.Request) :: Dict
    local uri = HTTP.URI(req.target)
    return HTTP.queryparams(uri.query)
end

"""
    html(content::String; status::Int, headers::Pair)

A convenience funtion to return a String that should be interpreted as HTML
"""
function html(content::String; status = 200, headers = ["Content-Type" => "text/html; charset=utf-8"]) :: HTTP.Response
    return HTTP.Response(status, headers, body = content)
end



"""
    redirect(path::String; code = 308)

return a redirect response 
"""
function redirect(path::String; code = 307)
    return HTTP.Response(code, ["Location" => path])
end


end