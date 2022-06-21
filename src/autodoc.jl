module AutoDoc 
using FromFile

@from "util.jl"     import Util: html
@from "Oxygen.jl"   import Oxygen: @get 

export registerchema, swaggerpath, schemapath, getschema, swaggerhtml, setupswagger, configdocs

global swaggerpath = "/swagger"
global schemapath = "/swagger/schema"

global schema = Dict(
    "openapi" => "3.0.0",
    "info" => Dict(
        "title" => "Simple API overview",
        "version" => "1.0.0"
    ),
    "paths" => Dict()
)

function getschema()
    return schema 
end

function configdocs(swagger_endpoint::String = swaggerpath, schema_endpoint::String = schemapath)
    global swaggerpath = swagger_endpoint
    global schemapath = schema_endpoint
end

function gettype(type)
    if type in [Float64, Float32, Float16]
        return "number"
    elseif type in [Int128, Int64, Int32, Int16, Int8]
        return "integer"
    elseif type isa Bool
        return "boolean"
    else 
        return "string"
    end
end

function registerchema(path::String, httpmethod::String, parameters, returntype::Array)

    # skip any routes that have to do with swagger
    if path in [swaggerpath, schemapath]
        return 
    end

    params = []
    for (name, type) in parameters
        param = Dict( 
            "in" => "path",
            "name" => "$name", 
            "required" => "true",
            "schema" => Dict(
                "type" => gettype(type)
            )
        )
        push!(params, param)
    end

    route = Dict(
        "$(lowercase(httpmethod))" => Dict(
            "parameters" => params,
            "responses" => Dict(
                "200" => Dict("description" => "200 response"),
                "500" => Dict("description" => "500 Server encountered a problem")
            )
        )
    )
    schema["paths"][path] = route 
end

# add the swagger and swagger/schema routes 
function setupswagger()
    
    @get "$swaggerpath" function()
        return html(swaggerhtml())
    end

    @get "$schemapath" function()
        return getschema() 
    end
    
end

# return the HTML to show the swagger docs
function swaggerhtml() :: String
    """
    <!DOCTYPE html>
    <html lang="en">
    
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="description" content="SwaggerUI" />
        <title>SwaggerUI</title>
        <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@4.5.0/swagger-ui.css" />
    </head>
    
    <body>
        <div id="swagger-ui"></div>
        <script src="https://unpkg.com/swagger-ui-dist@4.5.0/swagger-ui-bundle.js" crossorigin></script>
        <script>
            window.onload = () => {
                window.ui = SwaggerUIBundle({
                    url: window.location.origin + "$schemapath",
                    dom_id: '#swagger-ui',
                });
            };
        </script>
    </body>
    
    </html>
    """
end

end