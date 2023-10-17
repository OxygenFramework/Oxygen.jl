module OteraEngineTemplating
using MIMEs
using OteraEngine
include("util.jl"); using .TemplatingUtil

export otera

"""
    otera(template::String; kwargs...)

Create a function that renders an Otera `template` string with the provided `kwargs`.
If `template` is a file path, it reads the file content as the template string.
Returns a function that takes a dictionary `data` (default is an empty dictionary),
optional `status`, `headers`, and `template_kwargs`, and returns an HTTP Response object
with the rendered content.
"""
function otera(template::String; mime_type=nothing, kwargs...)
    is_file_path = isfile(template)
    mime_is_known = !isnothing(mime_type)

    # Case 1: a path to a file was passed
    if is_file_path
        if mime_is_known
            return otera(open(template); mime_type=mime_type, kwargs...)
        else
            # deterime the mime type based on the extension type 
            content_type = mime_from_path(template, MIME"application/octet-stream"()) |> contenttype_from_mime
            return otera(open(template); mime_type=content_type, kwargs...)
        end
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
        resp_headers = mime_is_known ? [["Content-Type" => mime_type]; headers] : headers
        response(content, status, resp_headers; detect=!mime_is_known)
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
    mime_is_known = !isnothing(mime_type)
    tmp = Template(template, path=false; kwargs...)

    return function(;tmp_init=nothing, jl_init=nothing, status=200, headers=[], template_kwargs...)
        combined_kwargs = Dict{Symbol, Any}(template_kwargs)
        if tmp_init !== nothing
            combined_kwargs[:tmp_init] = tmp_init
        end
        if jl_init !== nothing
            combined_kwargs[:jl_init] = jl_init
        end
        content = tmp(; combined_kwargs...)
        resp_headers = mime_is_known ? [["Content-Type" => mime_type]; headers] : headers
        response(content, status, resp_headers; detect=!mime_is_known)
    end

end

end