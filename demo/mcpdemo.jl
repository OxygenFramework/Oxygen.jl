module MCPDemo

using Oxygen
using HTTP
using Dates
using JSON

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

# `serve` mounts the MCP endpoint at `/mcp` once at least one tool is
# registered. Point an MCP client at http://127.0.0.1:8080/mcp.
serve()

end
