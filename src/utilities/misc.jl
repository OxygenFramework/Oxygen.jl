using HTTP 
using JSON3
using Dates

export countargs, recursive_merge, parseparam, 
    queryparams, redirect, handlerequest,
    format_response!, set_content_size!, format_sse_message


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
            if show_errors && !isa(error, InterruptException)
                 @error "ERROR: " exception=(error, catch_backtrace())
            end
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

function parseparam(::Type{Any}, rawvalue::String; escape=true)
    return escape ? HTTP.unescapeuri(rawvalue) : rawvalue
end

function parseparam(::Type{String}, rawvalue::String; escape=true)
    return escape ? HTTP.unescapeuri(rawvalue) : rawvalue
end

function parseparam(::Type{T}, rawvalue::String; escape=true) where {T <: Enum}
    return T(parse(Int, escape ? HTTP.unescapeuri(rawvalue) : rawvalue))
end

function parseparam(::Type{T}, rawvalue::String; escape=true) where {T <: Union{Date, DateTime}}
    return parse(T, escape ? HTTP.unescapeuri(rawvalue) : rawvalue)
end

function parseparam(::Type{T}, rawvalue::String; escape=true) where {T <: Union{Number, Char, Bool, Symbol}}
    return parse(T, escape ? HTTP.unescapeuri(rawvalue) : rawvalue)
end

function parseparam(::Type{T}, rawvalue::String; escape=true) where {T}
    return JSON3.read(escape ? HTTP.unescapeuri(rawvalue) : rawvalue, T)
end

"""
Iterate over the union type and parse the value with the first type that 
doesn't throw an erorr
"""
function parseparam(type::Union, rawvalue::String; escape=true)
    value::String = escape ? HTTP.unescapeuri(rawvalue) : rawvalue
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

function format_response!(req::HTTP.Request, content::AbstractString)
    # Dynamically determine the content type when given a string
    body = string(content)
    HTTP.setheader(req.response, "Content-Type" => HTTP.sniff(body))
    HTTP.setheader(req.response, "Content-Length" => string(sizeof(body)))

    req.response.status = 200
    req.response.body = content
end

function format_response!(req::HTTP.Request, content::Union{Number, Bool, Char, Symbol})
    # Convert all primitvies to a string and set the content type to text/plain
    body = string(content)
    HTTP.setheader(req.response, "Content-Type" => "text/plain; charset=utf-8")
    HTTP.setheader(req.response, "Content-Length" => string(sizeof(body)))

    req.response.status = 200
    req.response.body = body
end

function format_response!(req::HTTP.Request, content::Any)
    # Convert anthything else to a JSON string
    body = JSON3.write(content)
    HTTP.setheader(req.response, "Content-Type" => "application/json; charset=utf-8")
    HTTP.setheader(req.response, "Content-Length" => string(sizeof(body)))

    req.response.status = 200
    req.response.body = body    
end



"""
    format_sse_message(data::String; event::Union{String, Nothing} = nothing, id::Union{String, Nothing} = nothing)

Create a properly formatted Server-Sent Event (SSE) string.

# Arguments
- `data`: The data to send. This should be a string. Newline characters in the data will be replaced with separate "data:" lines.
- `event`: (optional) The type of event to send. If not provided, no event type will be sent. Should not contain newline characters.
- `retry`: (optional) The reconnection time for the event in milliseconds. If not provided, no retry time will be sent. Should be an integer.
- `id`: (optional) The ID of the event. If not provided, no ID will be sent. Should not contain newline characters.

# Notes
This function follows the Server-Sent Events (SSE) specification for sending events to the client.
"""
function format_sse_message(
    data    :: String; 
    event   :: Union{String, Nothing}   = nothing,
    retry   :: Union{Int, Nothing}      = nothing,
    id      :: Union{String, Nothing}   = nothing) :: String

    has_id = !isnothing(id) 
    has_retry = !isnothing(retry)
    has_event = !isnothing(event) 

    # check if event or id contain newline characters
    if has_id && contains(id, '\n')
        throw(ArgumentError("ID property cannot contain newline characters: $id"))
    end

    if has_event && contains(event, '\n')
        throw(ArgumentError("Event property cannot contain newline characters: $event"))
    end

    if has_retry && retry <= 0
        throw(ArgumentError("Retry property must be a positive integer: $retry"))
    end

    io = IOBuffer()
    
    # Make sure we don't send any newlines in the data proptery
    for line in split(data, '\n')
        write(io, "data: $line\n")
    end
    
    # Optional properties
    has_id     && write(io, "id: $id\n")
    has_retry  && write(io, "retry: $retry\n")
    has_event  && write(io, "event: $event\n")

    # Terminate the event, by marking it with a doubule newline
    write(io, "\n")

    # return the content of the buffer as a string
    return String(take!(io))
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




# """
#     generate_parser(func::Function, pathparams::Vector{Tuple{String,Type}})

# This function generates a parsing function specifically tailored to a given path.
# It generates parsing expressions for each parameter and then passes them to the given function. 

# ```julia

# # Here's an exmaple endpoint
# @get "/" function(req::HTTP.Request, a::Float64, b::Float64)
#     return a + b
# end

# # Here's the function that's generated by the macro
# function(func::Function, req::HTTP.Request)
#     # Extract the path parameters 
#     params = HTTP.getparams(req)
#     # Generate the parsing expressions
#     a = parseparam(Float64, params["a"])
#     b = parseparam(Float64, params["b"])
#     # Call the original function with the parsed parameters in the order they appear
#     func(req, a, b)
# end
# ```
# """
# function generate_parser(pathparams)    
#     # Extract the parameter names
#     func_args = [Symbol(param[1]) for param in pathparams]

#     # Create the parsing expressions for each path parameter
#     parsing_exprs = [
#         :( $(Symbol(param_name)) = parseparam($(param_type), params[$("$param_name")]) ) 
#         for (param_name, param_type) in pathparams
#     ]
#     quote 
#         function(func::Function, req::HTTP.Request)
#             # Extract the path parameters 
#             params = HTTP.getparams(req)
#             # Generate the parsing expressions
#             $(parsing_exprs...)
#             # Pass the func at runtime, so that revise can work with this
#             func(req, $(func_args...))
#         end
#     end |> eval
# end
