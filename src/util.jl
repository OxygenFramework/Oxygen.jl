module Util 
using HTTP 
using JSON3
using Dates

export countargs, recursive_merge, parseparam, queryparams, html, redirect

# return the number of args inside a function
function countargs(f::Function)
    return methods(f) |> first |> x -> x.nargs
end

# https://discourse.julialang.org/t/multi-layer-dict-merge/27261/7
recursive_merge(x::AbstractDict...) = merge(recursive_merge, x...)
recursive_merge(x...) = x[end]

function recursive_merge(x::AbstractVector...)
    elements = Dict()
    parameters = []
    flattened = cat(x...; dims=1)

    for item in flattened
        if !(item isa Dict) || !haskey(item, "name")
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


"""
Parse incoming path parameters into their corresponding type
ex.) parseparam(Float64, "4.6") => 4.6
"""
function parseparam(type::Type, rawvalue::String) 
    value::String = HTTP.unescapeuri(rawvalue)
    if type == Any || type == String 
        return value
    elseif type <: Enum
        return type(parse(Int, value))   
    elseif isprimitivetype(type) || type <: Number || type == Date || type == DateTime
        return parse(type, value)
    else 
        return JSON3.read(value, type)
    end 
end


"""
Iterate over the union type and parse the value with the first type that 
doesn't throw an erorr
"""
function parseparam(type::Union, rawvalue::String) 
    value::String = HTTP.unescapeuri(rawvalue)
    result = value 
    for current_type in Base.uniontypes(type)
        try 
            result = parseparam(current_type, value)
            break 
        catch 
            continue
        end
    end
    return result
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
function redirect(path::String; code = 307) :: HTTP.Response
    return HTTP.Response(code, ["Location" => path])
end


end