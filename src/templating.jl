module Templating
using HTTP
using MIMEs
using Mustache
using OteraEngine

export mustache, otera

"""
    response(content::String, status=200, headers=[]) :: HTTP.Response

Convert a template string `content` into a valid HTTP Response object.
The content type header is automatically generated based on the content's mimetype
- `content`: The string content to be included in the HTTP response body.
- `status`: The HTTP status code (default is 200).
- `headers`: Additional HTTP headers to include (default is an empty array).

Returns an `HTTP.Response` object with the specified content, status, and headers.
"""
function response(content::String, status=200, headers=[]; detect=true) :: HTTP.Response
    response_headers = detect ? ["Content-Type" => HTTP.sniff(content)] : []
    return HTTP.Response(status, [response_headers; headers;], content)
end

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

"""
    otera(template::String; kwargs...)

Create a function that renders an Otera `template` string with the provided `kwargs`.
If `template` is a file path, it reads the file content as the template string.
Returns a function that takes a dictionary `data` (default is an empty dictionary),
optional `status`, `headers`, and `template_kwargs`, and returns an HTTP Response object
with the rendered content.
"""
function otera(template::String; kwargs...)
    is_file_path = isfile(template)

    # Case 1: a path to a file was passed
    if is_file_path
        # deterime the mime type based on the extension type 
        content_type = mime_from_path(template, MIME"application/octet-stream"()) |> contenttype_from_mime
        return otera(open(template); mime_type=content_type, kwargs...)
    end

    # Case 2: A string template was passed directly
    tmp = Template(template, path=is_file_path; kwargs...)

    return function(;tmp_init=nothing, jl_init=nothing, status=200, headers=[], template_kwargs...)
        combined_kwargs = Dict{Symbol, Any}(template_kwargs)
        if tmp_init !== nothing
            combined_kwargs[:tmp_init] = tmp_init
        end
        if jl_init !== nothing
            combined_kwargs[:jl_init] = jl_init
        end
        content = tmp(; combined_kwargs...)
        response(content, status, headers)
    end

end


"""
    otera(file::IO; kwargs...)

Create a function that renders an Otera template from a file `file` with the provided `kwargs`.
Returns a function that takes a dictionary `data`, optional `status`, `headers`, and `template_kwargs`,
and returns an HTTP Response object with the rendered content.
"""
function otera(file::IO; mime_type=nothing, kwargs...)
    template = read(file, String)
    tmp = Template(template, path=false; kwargs...)
    
    function create_response(content, status, headers)
        if isnothing(mime_type)
            # case 1: No mime type is passed, so we should guess it based on the file contents
            return response(content, status, headers)
        else 
            # case 2: We have a mime type based on the file extension, so pass it directly
            return response(content, status, [["Content-Type" => mime_type]; headers]; detect=false)
        end
    end

    return function(;tmp_init=nothing, jl_init=nothing, status=200, headers=[], template_kwargs...)
        combined_kwargs = Dict{Symbol, Any}(template_kwargs)
        if !isnothing(tmp_init)
            combined_kwargs[:tmp_init] = tmp_init
        end
        if !isnothing(jl_init)
            combined_kwargs[:jl_init] = jl_init
        end
        content = tmp(; combined_kwargs...)
        create_response(content, status, headers)
    end
end

end