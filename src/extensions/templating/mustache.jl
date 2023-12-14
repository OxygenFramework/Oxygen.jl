module MustacheTemplating
using MIMEs
using Mustache
include("util.jl"); using .TemplatingUtil

export mustache


"""
    mustache(template::String; kwargs...)

Create a function that renders a Mustache `template` string with the provided `kwargs`.
If `template` is a file path, it reads the file content as the template string.
Returns a function that takes a dictionary `data`, optional `status`, and `headers`, and
returns an HTTP Response object with the rendered content.

To get more info read the docs here: https://github.com/jverzani/Mustache.jl
"""
function mustache(template::String; mime_type=nothing, from_file=false, kwargs...)
    mime_is_known = !isnothing(mime_type)

    # Case 1: a path to a file was passed
    if from_file
        if mime_is_known
            return mustache(open(template); mime_type=mime_type, kwargs...)
        else
            # deterime the mime type based on the extension type 
            content_type = mime_from_path(template, MIME"application/octet-stream"()) |> contenttype_from_mime
            return mustache(open(template); mime_type=content_type, kwargs...)
        end
    end

    # Case 2: A string template was passed directly
    function(data::AbstractDict = Dict(); status=200, headers=[])
        content = Mustache.render(template, data; kwargs...)        
        resp_headers = mime_is_known ? [["Content-Type" => mime_type]; headers] : headers
        response(content, status, resp_headers; detect=!mime_is_known)
    end
end

"""
    mustache(tokens::Mustache.MustacheTokens; kwargs...)

Create a function that renders a Mustache template defined by `tokens` with the provided `kwargs`.
Returns a function that takes a dictionary `data`, optional `status`, and `headers`, and
returns an HTTP Response object with the rendered content.

To get more info read the docs here: https://github.com/jverzani/Mustache.jl
"""
function mustache(tokens::Mustache.MustacheTokens; mime_type=nothing, kwargs...)
    mime_is_known = !isnothing(mime_type)
    return function(data::AbstractDict = Dict(); status=200, headers=[])
        content = Mustache.render(tokens, data; kwargs...)
        resp_headers = mime_is_known ? [["Content-Type" => mime_type]; headers] : headers
        response(content, status, resp_headers; detect=!mime_is_known)
    end 
end

"""
    mustache(file::IO; kwargs...)

Create a function that renders a Mustache template from a file `file` with the provided `kwargs`.
Returns a function that takes a dictionary `data`, optional `status`, and `headers`, and
returns an HTTP Response object with the rendered content.

To get more info read the docs here: https://github.com/jverzani/Mustache.jl
"""
function mustache(file::IO; mime_type=nothing, kwargs...)
    template = read(file, String)
    mime_is_known = !isnothing(mime_type)
    return function(data::AbstractDict = Dict(); status=200, headers=[])
        content = Mustache.render(template, data; kwargs...)
        resp_headers = mime_is_known ? [["Content-Type" => mime_type]; headers] : headers
        response(content, status, resp_headers; detect=!mime_is_known)
    end
end

end