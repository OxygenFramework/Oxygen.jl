module TimeZoneTests

using Test
using HTTP
using Dates
using TimeZones
using Oxygen

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

end