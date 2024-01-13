using HTTP
using MIMEs
using .OteraEngine

export otera

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
    otera(template::String; kwargs...)

Create a function that renders an Otera `template` string with the provided `kwargs`.
If `template` is a file path, it reads the file content as the template string.
Returns a function that takes a dictionary `data` (default is an empty dictionary),
optional `status`, `headers`, and `template_kwargs`, and returns an HTTP Response object
with the rendered content.

To get more info read the docs here: https://github.com/MommaWatasu/OteraEngine.jl
"""
function otera(template::String; mime_type=nothing, from_file=false, kwargs...)
    mime_is_known = !isnothing(mime_type)

    # Case 1: a path to a file was passed
    if from_file
        if mime_is_known
            return otera(open(template); mime_type=mime_type, kwargs...)
        else
            # deterime the mime type based on the extension type 
            content_type = mime_from_path(template, MIME"application/octet-stream"()) |> contenttype_from_mime
            return otera(open(template); mime_type=content_type, kwargs...)
        end
    end

    # Case 2: A string template was passed directly
    tmp = Template(template, path=from_file; kwargs...)
    return function(data = nothing; status=200, headers=[], template_kwargs...)
        combined_kwargs = Dict{Symbol, Any}(template_kwargs)
        if data !== nothing
            combined_kwargs[:init] = data
        end
        content = tmp(; combined_kwargs...)
        resp_headers = mime_is_known ? [["Content-Type" => mime_type]; headers] : headers
        response(content, status, resp_headers; detect=!mime_is_known)
    end
end


"""
    otera(file::IO; kwargs...)

Create a function that renders an Otera template from a file `file` with the provided `kwargs`.
Returns a function that takes a dictionary `data`, optional `status`, `headers`, and `template_kwargs`,
and returns an HTTP Response object with the rendered content.

To get more info read the docs here: https://github.com/MommaWatasu/OteraEngine.jl
"""
function otera(file::IO; mime_type=nothing, kwargs...)
    template = read(file, String)
    mime_is_known = !isnothing(mime_type)
    tmp = Template(template, path=false; kwargs...)
    
    return function(data = nothing; status=200, headers=[], template_kwargs...)
        combined_kwargs = Dict{Symbol, Any}(template_kwargs)
        if data !== nothing
            combined_kwargs[:init] = data
        end
        content = tmp(; combined_kwargs...)
        resp_headers = mime_is_known ? [["Content-Type" => mime_type]; headers] : headers
        response(content, status, resp_headers; detect=!mime_is_known)
    end
end

