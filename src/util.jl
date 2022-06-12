module Util 
using HTTP 

export method_argnames, queryparams, html

# https://discourse.julialang.org/t/get-the-argument-names-of-an-function/32902/4
function method_argnames(m::Method)
    argnames = ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), m.slot_syms)
    isempty(argnames) && return argnames
    return argnames[1:m.nargs]
end

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

end