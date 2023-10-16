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
"""
function mustache(template::String; kwargs...)
    # Case 1: a path to a file was passed
    if isfile(template)
        # deterime the mime type based on the extension type 
        content_type = mime_from_path(template, MIME"application/octet-stream"()) |> contenttype_from_mime
        return mustache(open(template); mime_type=content_type, kwargs...)
    end

    # Case 2: A string template was passed directly
    function(data::AbstractDict; status=200, headers=[])
        content = Mustache.render(template, data; kwargs...)
        response(content, status, headers)
    end
end

"""
    mustache(tokens::Mustache.MustacheTokens; kwargs...)

Create a function that renders a Mustache template defined by `tokens` with the provided `kwargs`.
Returns a function that takes a dictionary `data`, optional `status`, and `headers`, and
returns an HTTP Response object with the rendered content.
"""
function mustache(tokens::Mustache.MustacheTokens; kwargs...)
    return function(data::AbstractDict; status=200, headers=[])
        content = Mustache.render(tokens, data; kwargs...)
        response(content, status, headers)
    end 
end

"""
    mustache(file::IO; kwargs...)

Create a function that renders a Mustache template from a file `file` with the provided `kwargs`.
Returns a function that takes a dictionary `data`, optional `status`, and `headers`, and
returns an HTTP Response object with the rendered content.
"""
function mustache(file::IO; mime_type=nothing, kwargs...)
    template = read(file, String)
    return function(data::AbstractDict; status=200, headers=[])
        content = Mustache.render(template, data; kwargs...)
        if isnothing(mime_type)
            # case 1: No mime type is passed, so we should guess it based on the file contents
            return response(content, status, headers)
        else 
            # case 2: We have a mime type based on the file extension, so pass it directly
            return response(content, status, [["Content-Type" => mime_type]; headers]; detect=false)
        end
    end
end

end