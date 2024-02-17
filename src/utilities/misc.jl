using HTTP 
using JSON3
using Dates

export countargs, recursive_merge, parseparam, 
    queryparams, redirect, handlerequest,
    format_response!, set_content_size!


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
    redirect(path::String; code = 308)

return a redirect response 
"""
function redirect(path::String; code = 307) :: HTTP.Response
    return HTTP.Response(code, ["Location" => path])
end

function handlerequest(getresponse::Function, catch_errors::Bool; show_errors::Bool = true)
    if !catch_errors
        return getresponse()
    else 
        try 
            return getresponse()       
        catch error
            show_errors && @error "ERROR: " exception=(error, catch_backtrace())
            return json(("message" => "The Server encountered a problem"), status = 500)    
        end  
    end
end

"""
countargs(func)

Return the number of arguments of the first method of the function `f`.

# Arguments
- `f`: The function to get the number of arguments for.
"""
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
    Path Parameter Parsing functions
"""

function parseparam(type::Type{Any}, rawvalue::String)
    return HTTP.unescapeuri(rawvalue)
end

function parseparam(type::Type{String}, rawvalue::String)
    return HTTP.unescapeuri(rawvalue)
end

function parseparam(type::Type{T}, rawvalue::String) where {T <: Enum}
    return T(parse(Int, HTTP.unescapeuri(rawvalue)))
end

function parseparam(type::Type{T}, rawvalue::String) where {T <: Union{Date, DateTime}}
    return parse(T, HTTP.unescapeuri(rawvalue))
end

function parseparam(type::Type{T}, rawvalue::String) where {T <: Union{Number, Char, Bool, Symbol}}
    return parse(T, HTTP.unescapeuri(rawvalue))
end

function parseparam(type::Type{T}, rawvalue::String) where {T}
    return JSON3.read(HTTP.unescapeuri(rawvalue), T)
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


"""
    Response Formatter functions
"""

function format_response!(req::HTTP.Request, resp::HTTP.Response)
    # Return Response's as is without any modifications
    req.response = resp
end

function format_response!(req::HTTP.Request, content::String)
    # dynamically determine the content type
    push!(req.response.headers, "Content-Type" => HTTP.sniff(content), "Content-Length" => string(sizeof(content)))
    req.response.status = 200
    req.response.body = content
end

function format_response!(req::HTTP.Request, content::Any)
    # convert anthything else to a JSON string
    body = JSON3.write(content)
    push!(req.response.headers, "Content-Type" => "application/json; charset=utf-8", "Content-Length" => string(sizeof(body)))    
    req.response.status = 200
    req.response.body = body    
end


"""
    set_content_size!(body::Base.CodeUnits{UInt8, String}, headers::Vector; add::Bool, replace::Bool)

Set the "Content-Length" header in the `headers` vector based on the length of the `body`.

# Arguments
- `body`: The body of the HTTP response. This should be a `Base.CodeUnits{UInt8, String}`.
- `headers`: A vector of headers for the HTTP response.
- `add`: A boolean flag indicating whether to add the "Content-Length" header if it doesn't exist. Default is `false`.
- `replace`: A boolean flag indicating whether to replace the "Content-Length" header if it exists. Default is `false`.
"""
function set_content_size!(body::Union{Base.CodeUnits{UInt8, String}, Vector{UInt8}}, headers::Vector; add::Bool, replace::Bool)
    content_length_found = false
    for i in 1:length(headers)
        if headers[i].first == "Content-Length"
            if replace 
                headers[i] = "Content-Length" => string(sizeof(body))
            end
            content_length_found = true
            break
        end
    end
    if add && !content_length_found
        push!(headers, "Content-Length" => string(sizeof(body)))
    end
end

