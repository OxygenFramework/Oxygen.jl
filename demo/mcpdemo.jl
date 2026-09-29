module MCPDemo

using Oxygen
using HTTP
using Dates
using JSON
using Base64

### MCP tool input / output types ####

@kwdef struct Coordinates
    lat::Float64
    lon::Float64
end

@kwdef struct Place
    name::String
    coordinates::Coordinates
    tags::Vector{String} = String[]
end

@kwdef struct Site
    label::String
    place::Place
end

@kwdef struct Region
    name::String
    sites::Dict{String,Site} = Dict{String,Site}()
    visits::Vector{Site} = Site[]
end

@enum TemperatureUnit celsius = 1 fahrenheit = 2

### MCP tools ###

@tool "Add two integers together" Dict(
    :a => "the first addend", 
    :b => "the second addend"
    ) function add(a::Int, b::Int)
    return a + b
end

# Keyword arguments work too, and defaulted args are not required in the schema.
@tool "Greet someone by name" Dict(
    :name => "who to greet", 
    :greeting => "the greeting to use"
    ) function greet(name::String; greeting::String="Hello")
    return "$greeting, $(name)!"
end

# Enums are surfaced as integer `enum` values in the generated schema.
@tool "Convert a temperature" Dict(
    :value => "the temperature", 
    :from => "the source unit", 
    :to => "the target unit"
    ) function convert_temperature(value::Float64, from::TemperatureUnit, to::TemperatureUnit)
    from === to && return value
    if from === celsius
        return value * 9 / 5 + 32
    else
        return (value - 32) * 5 / 9
    end
end

# Nested struct arguments are decoded from JSON using the reflected schema.
@tool "Look up a saved place" Dict(:place => "the place to look up") function lookup_place(place::Place)
    return Dict(
        "name" => uppercase(place.name), 
        "lat" => place.coordinates.lat, 
        "lon" => place.coordinates.lon, 
        "tags" => place.tags
    )
end

# A map (`Dict`) and an array of nested structs are reflected recursively into
# the JSON Schema and decoded back into Julia values at call time.
@tool "Summarize a region" Dict(:region => "the region to summarize") function summarize_region(region::Region)
    return Dict(
        "name" => uppercase(region.name),
        "sites" => length(region.sites),
        "visits" => length(region.visits),
        "labels" => sort([site.label for site in values(region.sites)]),
        "first_visit" => isempty(region.visits) ? nothing : region.visits[1].place,
    )
end

# A streaming tool: progress notifications are emitted while the tool runs and
# delivered on the request-scoped SSE stream when the client sends a
# `_meta.progressToken`. The do-block's return value is still the final result;
# see `demo/mcpstreamingdemo.jl` for the explicit `progress(...)` form and a
# client that asserts frames arrive before the result.
@tool "Import a catalog" Dict(:urls => "catalog URLs") function import_catalog(urls::Vector{String})
    return mcp_stream() do stream
        for url in urls
            sleep(0.2)  # stand-in for real work
            put!(stream, "imported $url")  # auto-numbered progress notification
        end
        return "Imported $(length(urls)) records"
    end
end

### MCP prompts ###

# Prompts are user-controlled message templates exposed via `prompts/list` and
# `prompts/get`. There is no parameter description dictionary; the handler's own
# parameters are the prompt arguments. Parameters without a default are required.
@prompt "Plan a trip to a place" function trip_plan(place::String, days::Int=3)
    return "Plan a $days-day trip to $place."
end

# Returning a `String` produces a single user message; return `role => content`
# pairs (or a vector mixing pairs and content) to build a multi-message prompt.
# Only "user" and "assistant" roles are allowed.
@prompt "Review a saved place" function review_place(place::String, style::String="concise")
    return ["user" => "Write a $style review of $place.",
            "assistant" => "Sure, what should it focus on?",
            "user" => "Its coordinates, tags, and nearby sites."]
end

### MCP resources ###

# Sample data used by the resource examples below.
const PLACES = Dict(
    "seattle" => Place("Seattle", Coordinates(47.61, -122.33), ["coffee", "rain"]),
    "kyoto" => Place("Kyoto", Coordinates(35.01, 135.77), ["temples", "gardens"]),
)

# Static resources have a concrete URI and take no handler arguments beyond the
# injected `context`/`request`. The returned value becomes the read result:
# strings are `text`, raw bytes become a base64 `blob` for binary media, and
# HTTP responses honor their Content-Type.
@resource "oxygen://readme" "Project readme" function readme_resource()
    return "# Oxygen MCP demo\n\nThis server exposes tools, prompts, and resources."
end

# A complete 1x1 PNG so clients can actually render the returned `blob`.
const LOGO_PNG = base64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

# Returning raw bytes or an `HTTP.Response` exercises the base64 `blob` path.
@resource "oxygen://logo" "Demo icon" function logo_resource()
    return HTTP.Response(200, ["Content-Type" => "image/png"], LOGO_PNG)
end

# A static resource returning JSON text. Returning a dictionary types the read
# reply as `application/json`, matching the template below.
@resource "oxygen://places" "All saved places" function places_resource()
    return Dict("places" => sort([place.name for place in values(PLACES)]))
end

# A URI with `{var}` placeholders is a resource template: the handler's
# parameters are the template variables, and captured values are percent-decoded
# and coerced to the declared types. Returning a dictionary is serialized as
# JSON text.
@resource "oxygen://places/{name}" "Look up a place by name" function place_resource(name::String)
    place = get(PLACES, lowercase(name), nothing)
    isnothing(place) && return "Unknown place: $name"
    return Dict(
        "name" => place.name,
        "lat" => place.coordinates.lat,
        "lon" => place.coordinates.lon,
        "tags" => place.tags,
    )
end

# The function form supports explicit metadata; `mime_type` becomes the fallback
# content type of the read reply.
function config_resource()
    return JSON.json(Dict("debug" => false, "retries" => 3))
end

resource("oxygen://config", "Server configuration", config_resource;
         title="Server configuration", mime_type="application/json")

# A mutation tool: after changing server state it calls
# `notify_resource_updated`, so subscribed clients re-read `oxygen://places`.
# Modern clients receive it on a `subscriptions/listen` stream, legacy clients
# via `resources/subscribe`. List changes (`notify_tools_changed`, etc.) are
# published automatically by the registration functions.
@tool "Add a place to the demo registry" Dict(
    :name => "the place name",
    :lat => "latitude",
    :lon => "longitude",
    ) function add_place(name::String, lat::Float64, lon::Float64)
    PLACES[lowercase(name)] = Place(name, Coordinates(lat, lon), String[])
    notify_resource_updated("oxygen://places")
    return "Added $name"
end

### Health check endpoints ####################################################

# Captured once at startup so the health endpoints can report uptime.
const START_TIME = now()

function uptime_seconds()::Int
    return round(Int, Dates.value(now() - START_TIME) / 1000)
end

# Aggregate health report, handy as a single endpoint for dashboards.
@get "/health" function()
    return text("ALIVE")
end

@get "/" function()
    return text("Welcome to the Oxygen MCP server")
end

# `serve` mounts the MCP endpoint at `/mcp` once at least one tool, prompt, or
# resource is registered. Point an MCP client at http://127.0.0.1:8080/mcp.
serve()

end
