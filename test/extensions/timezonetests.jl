module TimeZoneTests

using Test
using JSON3
using HTTP
using Dates
using TimeZones
using Oxygen; @oxidise
using ..Constants
using ..TestUtils

# This is the default format given from JS when creating a new date and calling toISOString()
@testset "UTC ISO 8601 String Parsing Test" begin
    dt = parse(ZonedDateTime, "2025-01-01T20:30:20.620Z")
    @test dt isa ZonedDateTime
    @test year(dt) == 2025
    @test month(dt) == 1
    @test day(dt) == 1
    @test hour(dt) == 20
    @test minute(dt) == 30
    @test second(dt) == 20
    @test millisecond(dt) == 620
end

# For all other timezones, the offset is included in the string like this
@testset "Offset ISO 8601 String Parsing Test" begin 
    dt = parse(ZonedDateTime, "2025-02-02T22:25:31.035+07:00")
    @test dt isa ZonedDateTime
    @test year(dt) == 2025
    @test month(dt) == 2
    @test day(dt) == 2
    @test hour(dt) == 22
    @test minute(dt) == 25
    @test second(dt) == 31
    @test millisecond(dt) == 35
end

# Test using it directly as a path parameter
@get "/time/{time}" function(req, time::ZonedDateTime)
    return "current date: $time" |> text
end

struct TimePayload
    time::ZonedDateTime
end

@post "/time" function(req, payload::Json{TimePayload})
    return "The date is $(payload.payload.time)" |> text
end

ctx = CONTEXT[]
components = ctx.docs.schema["components"]["schemas"]
paths = ctx.docs.schema["paths"]

@testset "TimeZones component generation check" begin 
    # ensure schemas are present for all types
    @test haskey(components, "TimePayload")

    # ensure the generated Car schema aligns
    time_payload = components["TimePayload"]
    @test time_payload["type"] == "object"
    @test_has_key_and_values time_payload "required" ["time"]
    @test time_payload["properties"]["time"]["type"] == "string"
    @test time_payload["properties"]["time"]["format"] == "date-time"
end

@testset "TimeZones Path param checks" begin 
    params = paths["/time/{time}"]["get"]["parameters"]
    first_param = first(params)

    @test first_param["name"] == "time"
    @test first_param["required"] == true
    @test first_param["in"] == "path"
    @test first_param["schema"]["format"] == "date-time"
    @test first_param["schema"]["type"] == "string"
end

@testset "TimeZones Json body checks" begin 
    req_body = paths["/time"]["post"]["requestBody"]
    @test req_body["content"]["application/json"]["schema"]["type"] == "object"
    @test req_body["content"]["application/json"]["schema"]["allOf"][1]["\$ref"] == "#/components/schemas/TimePayload"
end

serve(host=HOST, port=PORT, async=true, show_banner=false, access_log=nothing)

@testset "Test ZonedDateTime as a Path Param" begin 
    r = HTTP.get("$localhost/time/2025-02-02T22:25:31.035+07:00")
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/plain; charset=utf-8"
    @test text(r) == "current date: 2025-02-02T22:25:31.035+07:00"
end

@testset "Test ZonedDateTime within a json body" begin 
    r = HTTP.post("$localhost/time", body=JSON3.write(Dict("time" => "2025-02-02T22:25:31.035+07:00")))
    @test r.status == 200
    @test HTTP.header(r, "Content-Type") == "text/plain; charset=utf-8"
    @test text(r) == "The date is 2025-02-02T22:25:31.035+07:00"
end

terminate()

end