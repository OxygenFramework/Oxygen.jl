module AutoDoc
using HTTP
using Dates
using DataStructures
using Reexport
using RelocatableFolders

using ..Util: html, recursive_merge
using ..Constants
using ..AppContext: Context, Documenation
using ..Types: TaggedRoute, TaskDefinition, CronDefinition, Nullable, Param, isrequired
using ..Extractors: isextractor, extracttype, isreqparam
using ..Reflection: splitdef

export registerschema, swaggerhtml, redochtml, mergeschema

"""
    mergeschema(route::String, customschema::Dict)

Merge the schema of a specific route
"""
function mergeschema(schema::Dict, route::String, customschema::Dict)
    schema["paths"][route] = recursive_merge(get(schema["paths"], route, Dict()), customschema)
end


"""
    mergeschema(customschema::Dict)

Merge the top-level autogenerated schema with a custom schema
"""
function mergeschema(schema::Dict, customschema::Dict)
    updated_schema = recursive_merge(schema, customschema)
    merge!(schema, updated_schema)
end


"""
Returns the openapi equivalent of each Julia type
"""
function gettype(type::Type)::String
    if type <: Bool
        return "boolean"
    elseif type <: AbstractFloat
        return "number"
    elseif type <: Integer
        return "integer"
    elseif type <: AbstractVector
        return "array"
    elseif type <: String || type == Date || type == DateTime
        return "string"
    elseif isstructtype(type)
        return "object"
    else
        return "string"
    end
end

"""
Returns the specific format type for a given parameter
ex.) DateTime(2022,1,1) => "date-time"
"""
function getformat(type::Type) :: Nullable{String}
    if type <: AbstractFloat
        if type == Float32
            return "float"
        elseif type == Float64
            return "double"
        end
    elseif type <: Integer
        if type == Int32
            return "int32"
        elseif type == Int64
            return "int64"
        end
    elseif type == Date
        return "date"
    elseif type == DateTime
        return "date-time"
    end
    return nothing
end

function createparam(p::Param{T}, paramtype::String) :: Dict where {T}
    param = Dict(
        "in" => paramtype,          # path, query, header (where the parameter is located)
        "name" => String(p.name),
        "required" => paramtype == "path" ? true : isrequired(p), # path params are always required
        "schema" => Dict(
            "type" => gettype(p.type)
        )
    )
    format = getformat(p.type)
    if !isnothing(format)
        param["schema"]["format"] = format
    end
    return param
end


"""
Used to generate & register schema related for a specific endpoint 
"""
function registerschema(
    docs::Documenation,
    path::String,
    httpmethod::String,
    parameters::Vector,
    queryparams::Vector,
    headers::Vector,
    bodyparams::Vector,
    returntype::Vector)

    ##### Add all the body parameters to the schema #####

    schemas = Dict()
    for p in bodyparams
        inner_type = p.type |> extracttype
        convertobject!(inner_type, schemas)
    end

    components = Dict("components" => Dict("schemas" => schemas))
    if !isempty(schemas)
        mergeschema(docs.schema, components)
    end

    ##### Create the parameters for the route #####

    params = []

    function formatparam(p::Param{T}, paramtype::String) where {T}
        # Will need to flatten request extrators & append all properties to the schema
        if isextractor(p) && isreqparam(p)
            type = extracttype(p.type)
            info = splitdef(type)
            sig_names = OrderedSet{Symbol}(p.name for p in info.sig)
            for name in sig_names
                p = info.sig_map[name]
                param = createparam(p, paramtype)
                push!(params, param)
            end
        else
            param = createparam(p, paramtype)
            push!(params, param)
        end
    end
    
    for p in parameters
        formatparam(p, "path")
    end

    for p in queryparams
        formatparam(p, "query")
    end

    for p in headers
        formatparam(p, "header")
    end

    # lookup if this route has any registered tags
    if haskey(docs.taggedroutes, path) && httpmethod in docs.taggedroutes[path].httpmethods
        tags = docs.taggedroutes[path].tags
    else
        tags = []
    end

    route = Dict(
        "$(lowercase(httpmethod))" => Dict(
            "tags" => tags,
            "parameters" => params,
            "responses" => Dict(
                "200" => Dict("description" => "200 response"),
                "500" => Dict("description" => "500 Server encountered a problem")
            )
        )
    )
   
    # collect a list of all references to the body parameters
    body_refs = Dict{String,Vector{String}}()
    for p in bodyparams
        inner_type = p.type |> extracttype |> nameof |> string
        extractor_name = p.type |> nameof |> string

        if !haskey(body_refs, extractor_name)
            body_refs[extractor_name] = []
        end

        body_refs[extractor_name] = vcat(body_refs[extractor_name], "#/components/schemas/$inner_type")
        # push!(refs, "#/components/schemas/$inner_type")
    end

    jsonschema = collectschemarefs(body_refs, ["Json", "JsonFragment"])
    jsonschema = merge(jsonschema, Dict("type" => "object"))

    textschema = collectschemarefs(body_refs, ["Body"])
    textschema = merge(textschema, Dict("type" => "number"))

    formschema = collectschemarefs(body_refs, ["Form"])
    formschema = merge(formschema, Dict("type" => "object"))

    content = Dict(
        "application/json" => Dict(
            "schema" => jsonschema
        ),
        "text/plain" => Dict(
            "schema" => textschema
        ),
        "application/x-www-form-urlencoded" => Dict(
            "schema" => formschema
        ),
        "application/xml" => Dict(
            "schema" => Dict(
                "type" => "object"
            )
        ),
        "multipart/form-data" => Dict(
            "schema" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "file" => Dict(
                        "type" => "string",
                        "format" => "binary"
                    )
                ),
                "required" => ["file"]
            )
        )
    )

    ordered_content = OrderedDict()

    if !isempty(jsonschema["allOf"])
        ordered_content["application/json"] = Dict("schema" => jsonschema)
    end

    if !isempty(textschema["allOf"])
        ordered_content["text/plain"] = Dict("schema" => textschema)
    end

    if !isempty(formschema["allOf"])
        ordered_content["application/x-www-form-urlencoded"] = Dict("schema" => formschema)
    end

    # Add in missing keys
    for (key, value) in content
        if !haskey(ordered_content, key)
            ordered_content[key] = value
        end
    end

    # Add a request body to the route if it's a POST, PUT, or PATCH request
    if httpmethod in ["POST", "PUT", "PATCH"] || !isempty(bodyparams)
        route[lowercase(httpmethod)]["requestBody"] = Dict(
            "required" => false,
            "content" => ordered_content
        )
    end

    # remove any special regex patterns from the path before adding this path to the schema
    cleanedpath = replace(path, r"(?=:)(.*?)(?=}/)" => "")
    mergeschema(docs.schema, cleanedpath, route)
end

function collectschemarefs(data::Dict, keys::Vector{String}; schematype="allOf")
    refs = []
    for key in keys
        if haskey(data, key)
            append!(refs, data[key])
        end
    end
    return Dict("$schematype" => [ Dict("\$ref" => ref) for ref in refs ])
end


function is_custom_struct(T::Type)
    return isstructtype(T) && T.name.module ∉ (Base, Core)
end

# takes a struct and converts it into an openapi 3.0 compliant dictionary
function convertobject!(type::Type, schemas::Dict) :: Dict

    typename = type |> nameof |> string

    # intilaize this entry
    obj = Dict("type" => "object", "properties" => Dict())

    # iterate over fieldnames
    for field in fieldnames(type)
        current_type = fieldtype(type, field)
        current_name = string(nameof(current_type))
        if is_custom_struct(current_type) && !haskey(schemas, current_name)
            # Set the field to be a reference to the custom struct
            obj["properties"][string(field)] = Dict("\$ref" => "#/components/schemas/$current_name")
            # Recursively convert nested structs
            convertobject!(current_type, schemas)
        else
            # convert the current field
            obj["properties"][string(field)] = Dict("type" => gettype(current_type))
        end
    end

    schemas[typename] = obj

    return schemas
end

"""
Read in a static file from the /data folder
"""
function readstaticfile(filepath::String)::String
    path = joinpath(DATA_PATH, filepath)
    return read(path, String)
end


function redochtml(schemapath::String, docspath::String)::HTTP.Response
    redocjs = readstaticfile("$REDOC_VERSION/redoc.standalone.js")

    html("""
    <!DOCTYPE html>
    <html lang="en">

        <head>
            <title>Docs</title>
            <meta charset="utf-8"/>
            <meta name="description" content="Docs" />
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link rel="icon" type="image/x-icon" href="$docspath/metrics/favicon.ico">
        </head>
        
        <body>
            <redoc spec-url="$schemapath"></redoc>
            <script>$redocjs</script>
        </body>

    </html>
    """)
end


"""
Return HTML page to render the autogenerated docs
"""
function swaggerhtml(schemapath::String, docspath::String)::HTTP.Response

    # load static content files
    swaggerjs = readstaticfile("$SWAGGER_VERSION/swagger-ui-bundle.js")
    swaggerstyles = readstaticfile("$SWAGGER_VERSION/swagger-ui.css")

    html("""
        <!DOCTYPE html>
        <html lang="en">
        
        <head>
            <title>Docs</title>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <meta name="description" content="Docs" />
            <style>$swaggerstyles</style>
            <link rel="icon" type="image/x-icon" href="$docspath/metrics/favicon.ico">
        </head>
        
        <body>
            <div id="swagger-ui"></div>
            <script>$swaggerjs</script>
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
    """)
end

end
