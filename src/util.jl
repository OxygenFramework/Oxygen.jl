module Util 
using HTTP 
using JSON3

export method_argnames, recursive_merge, queryparams, html, redirect

# https://discourse.julialang.org/t/get-the-argument-names-of-an-function/32902/4
function method_argnames(m::Method)
    argnames = ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), m.slot_syms)
    isempty(argnames) && return argnames
    return argnames[1:m.nargs]
end

# https://discourse.julialang.org/t/multi-layer-dict-merge/27261/7
recursive_merge(x::AbstractDict...) = merge(recursive_merge, x...)
recursive_merge(x...) = x[end]

function recursive_merge(x::AbstractVector...)
    elements = Dict()
    parameters = []
    flattened = cat(x...; dims=1)
    for item in flattened
        if !haskey(item, "name")
            continue
        end
        if haskey(elements, item["name"])
            elements[item["name"]] = recursive_merge(elements[item["name"]], item)
        else 
            elements[item["name"]] = item
            if !(item["name"] in parameters)
                push!(parameters, item["name"])
            end
        end
    end
    
    if !isempty(parameters)
        return [ elements[name] for name in parameters ]
    else
        return flattened
    end
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



"""
    redirect(path::String; code = 308)

return a redirect response 
"""
function redirect(path::String; code = 307)
    return HTTP.Response(code, ["Location" => path])
end


end