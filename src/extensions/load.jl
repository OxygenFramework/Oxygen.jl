using Requires

const PNG   = MIME"image/png"()
const SVG   = MIME"image/svg+xml"()
const PDF   = MIME"application/pdf"()
const HTML  = MIME"text/html"()

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
    response = HTTP.Response(status, headers, content)
    detect && HTTP.setheader(response, "Content-Type" => HTTP.sniff(content))
    HTTP.setheader(response, "Content-Length" => string(sizeof(content)))
    return response
end

function __init__()


    ################################################################
    #                       Serialization Extensions               #
    ################################################################
    @require ProtoBuf = "3349acd9-ac6a-5e09-bcdb-63829b23a429" include("serialization/protobuf.jl")


    ################################################################
    #                       Templating Extensions                  #
    ################################################################
    @require Mustache="ffc61752-8dc7-55ee-8c37-f3e9cdd09e70" include("templating/mustache.jl")
    @require OteraEngine="b2d7f28f-acd6-4007-8b26-bc27716e5513" include("templating/oteraengine.jl")


    ################################################################
    #                       Plotting Extensions                    #
    ################################################################
    @require CairoMakie="13f3f980-e62b-5c42-98c6-ff1f3baf88f0" include("plotting/cairomakie.jl")
    @require Bonito="824d6782-a2ef-11e9-3a09-e5662e0c26f8" include("plotting/bonito.jl")
    @require WGLMakie="276b4fcb-3e11-5398-bf8b-a0c2d153d008" begin 
        @require Bonito="824d6782-a2ef-11e9-3a09-e5662e0c26f8" begin
            include("plotting/wglmakie.jl")
        end
    end
    
end
