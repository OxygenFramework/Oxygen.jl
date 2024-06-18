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

function getcomponent(name::AbstractString) :: String
    return "#/components/schemas/$name"
end

function getcomponent(t::DataType) :: String
    return getcomponent(string(nameof(t)))
end

function createparam(p::Param{T}, paramtype::String) :: Dict where {T}

    schema = Dict("type" => gettype(p.type))

    # Add ref if the type is a custom struct
    if schema["type"] == "object"
        schema["\$ref"] = getcomponent(p.type)
    end

    # Add optional format if it's relevant
    format = getformat(p.type)
    if !isnothing(format)
        schema["format"] = format
    end

    # path params are always required
    param_required = paramtype == "path" ? true : isrequired(p), 

    param = Dict(
        "in" => paramtype, # path, query, header (where the parameter is located)
        "name" => String(p.name),
        "required" => param_required,
        "schema" => schema
    )

    return param
end

"""
This function helps format the individual parameters for each route in the openapi schema
"""
function formatparam!(params::Vector{Any}, p::Param{T}, paramtype::String) where T
    # Will need to flatten request extrators & append all properties to the schema
    if isextractor(p) && isreqparam(p)
        type = extracttype(p.type)
        info = splitdef(type)
        sig_names = OrderedSet{Symbol}(p.name for p in info.sig)
        for name in sig_names
            push!(params, createparam(info.sig_map[name], paramtype))
        end
    else
        push!(params, createparam(p, paramtype))
    end
end


"""
This function helps format the content object for each route in the openapi schema.

If similar body extractors are used, all schema's are included using an "allOf" relation.
The only exception to this is the text/plain case, which excepts the Body extractor. 
If there are more than one Body extractor, the type defaults to string - since this is 
the only way to represent multiple formats at the same time.
"""
function formatcontent(bodyparams::Vector) :: OrderedDict

    body_refs = Dict{String,Vector{String}}()
    body_types = Dict()

    for p in bodyparams

        inner_type      = p.type |> extracttype
        inner_type_name = inner_type |> nameof |> string
        extractor_name  = p.type |> nameof |> string
        body_types[extractor_name] = gettype(inner_type)

        if !is_custom_struct(inner_type)
            continue
        end

        if !haskey(body_refs, extractor_name)
            body_refs[extractor_name] = []
        end

        body_refs[extractor_name] = vcat(body_refs[extractor_name], getcomponent(inner_type_name))
    end

    jsonschema = collectschemarefs(body_refs, ["Json", "JsonFragment"])
    jsonschema = merge(jsonschema, Dict("type" => "object"))

    # The schema type for text/plain can vary unlike the other types
    textschema = collectschemarefs(body_refs, ["Body"])
    # If there are multiple Body extractors, default to string type
    textschema_type = length(textschema["allOf"]) > 1 ? "string" : get(body_types, "Body", "string") 
    textschema = merge(textschema, Dict("type" => textschema_type))

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

    ##### Add Schemas to this route, with the preferred content type first #####
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

    # Add all other content types (won't default to these, but they are available)
    for (key, value) in content
        if !haskey(ordered_content, key)
            ordered_content[key] = value
        end
    end

    return ordered_content
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
        if is_custom_struct(inner_type)
            convertobject!(inner_type, schemas)
        end
    end

    components = Dict("components" => Dict("schemas" => schemas))
    if !isempty(schemas)
        mergeschema(docs.schema, components)
    end

    ##### Append the parameter schema for the route #####
    params = []

    for (param_list, location) in [(parameters, "path"), (queryparams, "query"), (headers, "header")]
        for p in param_list
            formatparam!(params, p, location)
        end
    end

    ##### Set the schema for the body parameters #####   
    content = formatcontent(bodyparams)
 
    # lookup if this route has any registered tags
    if haskey(docs.taggedroutes, path) && httpmethod in docs.taggedroutes[path].httpmethods
        tags = docs.taggedroutes[path].tags
    else
        tags = []
    end

    # Build the route schema
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
    
    # Add a request body to the route if it's a POST, PUT, or PATCH request
    if httpmethod in ["POST", "PUT", "PATCH"] || !isempty(bodyparams)
        route[lowercase(httpmethod)]["requestBody"] = Dict(
            # if any body param is required, mark the entire body as required
            "required" => any(p -> isrequired(p), bodyparams),
            "content" => content
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
    return T.name.module ∉ (Base, Core) && (isstructtype(T) || isabstracttype(T))
end

# takes a struct and converts it into an openapi 3.0 compliant dictionary
function convertobject!(type::Type, schemas::Dict) :: Dict

    typename = type |> nameof |> string

    # intilaize this entry
    obj = Dict("type" => "object", "properties" => Dict())

    # parse out the fields of the type
    info = splitdef(type)

    # Make sure we have a unique set of names (in case of duplicate field names when parsing types)
    # The same field names can show up as regular parameters and keyword parameters when the type is used with @kwdef
    sig_names = OrderedSet{Symbol}(p.name for p in info.sig)

    # loop over all unique fields
    for name in sig_names
        
        p = info.sig_map[name]
        field_name = string(p.name)
        current_type = p.type
        current_name = string(nameof(current_type))

        # Case 1: Recursively convert nested structs & register schemas
        if is_custom_struct(current_type) && !haskey(schemas, current_name)
            # Set the field to be a reference to the custom struct
            obj["properties"][field_name] = Dict("\$ref" => getcomponent(current_name))
            # Recursively convert nested structs
            convertobject!(current_type, schemas)

        # Case 2: Convert the individual fields of the current type to it's openapi equivalent
        else
            current_field = Dict("type" => gettype(current_type), "required" => isrequired(p))

            # Add format if it exists
            format = getformat(current_type)
            if !isnothing(format)
                current_field["format"] = format
            end

            # convert the current field
            obj["properties"][field_name] = current_field
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


function redochtml(schemapath::String, docspath::String) :: HTTP.Response
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
function swaggerhtml(schemapath::String, docspath::String) :: HTTP.Response

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
