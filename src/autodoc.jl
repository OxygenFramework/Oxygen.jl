module AutoDoc 
using HTTP
using Dates

include("util.jl"); using .Util 

export registerchema, docspath, schemapath, getschema, 
    swaggerhtml, configdocs, mergeschema, setschema, router,
    enabledocs, disabledocs, isdocsenabled, registermountedfolder, 
    getrepeatasks, getmiddleware

struct TaggedRoute 
    httpmethods::Vector{String} 
    tags::Vector{String}
end

global enable_auto_docs = true 
global docspath = "/docs"
global schemapath = "/docs/schema"
global mountedfolders = Set{String}()
global taggedroutes = Dict{String, TaggedRoute}()
global repeattasks = []
global const routermiddlware = Ref{Dict{String,Vector{Function}}}(Dict())

global schema = Dict(
    "openapi" => "3.0.0",
    "info" => Dict(
        "title" => "API Overview",
        "version" => "1.0.0"
    ),
    "paths" => Dict()
)

function getrepeatasks()
    return repeattasks
end

"""
Registers the folder as a source for mounting static files
"""
function registermountedfolder(folder::String)
    push!(mountedfolders, "/$folder")
end

"""
    isdocsenabled()

Returns true if we should mount the api doc endpoints, false otherwise
"""
function isdocsenabled()
    return enable_auto_docs
end

"""
    enabledocs()

Tells the api to mount the api doc endpoints on startup
"""
function enabledocs()
    global enable_auto_docs = true 
end

"""
    disabledocs()

Tells the api to SKIP mounting the api doc endpoints on startup
"""
function disabledocs()
    global enable_auto_docs = false 
end

"""
    configdocs(docs_url::String = "/docs", schema_url::String = "/docs/schema")

Configure the default docs and schema endpoints
"""
function configdocs(docs_url::String = docspath, schema_url::String = schemapath)
    global docspath = docs_url
    global schemapath = schema_url
end

"""
    getschema()

Return the current internal schema for this app
"""
function getschema()
    return schema 
end

"""
    setschema(customschema::Dict)

Overwrites the entire internal schema
"""
function setschema(customschema::Dict)
    global schema = customschema
end


"""
    mergeschema(route::String, customschema::Dict)

Merge the schema of a specific route
"""
function mergeschema(route::String, customschema::Dict)
    global schema["paths"][route] = recursive_merge(schema["paths"][route], customschema)
end


"""
    mergeschema(customschema::Dict)

Merge the top-level autogenerated schema with a custom schema
"""
function mergeschema(customschema::Dict)
    global schema = recursive_merge(getschema(), customschema)
end

function getmiddleware()
    return routermiddlware[]
end

"""
    router(prefix::String; tags::Vector{String} = [], interval::Union{Real, Nothing} = nothing)

This functions assists registering routes with a specific prefix.
You can optionally assign tags either at the prefix and/or route level which
are used to group and organize the autogenerated documentation
"""
function router(prefix::String = ""; tags = Vector{String}(), middleware = Vector(), interval::Union{Real, Nothing} = nothing)
    return createrouter(prefix, tags, middleware, interval)
end

function createrouter(prefix::String, routertags::Vector{String}, routermiddleware::Vector, routerinterval::Union{Real, Nothing})

    # appends a "/" character to the given string if doesn't have one. 
    function fixpath(path::String)
        if !isnothing(path) && !isempty(path)
            return startswith(path, "/") ? path : "/$path"
        end
        return ""
    end

    # This function takes input from the user next to the request handler
    return function(path = nothing; tags = Vector{String}(), middleware = Vector(), interval::Union{Real, Nothing} = routerinterval)
        combinedtags = [tags..., routertags...]
        combinedmiddleware = [middleware..., routermiddleware...]

        # this is called inside the @register macro (only it knows the exact httpmethod associated with each path)
        return function(httpmethod::String)

            # combine the current routers prefix with this specfic path 
            path = !isnothing(path) ? "$(fixpath(prefix))$(fixpath(path))" : fixpath(prefix)

            # register the router & route specific middleware
            getmiddleware()[path] = combinedmiddleware
            
            # register interval for this route 
            if !isnothing(interval) && interval >= 0.0
                push!(repeattasks, (path, httpmethod, interval))
            end

            # register tags
            if !haskey(taggedroutes, path)
                taggedroutes[path] = TaggedRoute([httpmethod], combinedtags)
            else 
                combinedmethods = vcat(httpmethod, taggedroutes[path].httpmethods)
                taggedroutes[path] = TaggedRoute(combinedmethods, combinedtags)
            end

            return path 
        end
    end
end


"""
Returns the openapi equivalent of each Julia type
"""
function gettype(type::Type) :: String
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
function getformat(type::Type) :: Union{String,Nothing}
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



"""
Used to generate & register schema related for a specific endpoint 
"""
function registerchema(path::String, httpmethod::String, parameters, returntype::Array)

    # skip docs & schema paths 
    if path in [docspath, schemapath]
        return 
    end

    params = []
    for (name, type) in parameters
        format = getformat(type)
        param = Dict( 
            "in" => "path",
            "name" => "$name", 
            "required" => "true",
            "schema" => Dict(
                "type" => gettype(type)
            )
        )
        if !isnothing(format)
            param["schema"]["format"] = format
        end
        push!(params, param)
    end

    is_mounted_path = false
    for folder in mountedfolders
        if startswith(path, folder)
            is_mounted_path = true
            break 
        end
    end

    if is_mounted_path
        return 
    end

    # lookup if this route has any registered tags
    if haskey(taggedroutes, path) && httpmethod in taggedroutes[path].httpmethods
        tags = taggedroutes[path].tags 
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
    schema["paths"][path] = route 
end

"""
Return HTML page to render the autogenerated docs
"""
function swaggerhtml() :: HTTP.Response
    html("""
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
    )
end

end