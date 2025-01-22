module AutoDocTests

using Test
using Oxygen; @oxidise
using ..Constants

struct Car
    name::String
end

struct Person 
    name::String
    car::Car
end

struct Party
    guests::Vector{Person}
end

# This will do a recursive dive on the 'Party' type and generate the schema for all structs
@post "/invite-all" function(req, party::Json{Party})
    return text("added $(length(party.payload.guests)) guests")
end

ctx = CONTEXT[]
schemas = ctx.docs.schema["components"]["schemas"]

@testset "schema gen tests" begin 

    # ensure schemas are present for all types
    @test haskey(schemas, "Car")
    @test haskey(schemas, "Person")
    @test haskey(schemas, "Party")

    # ensure the generated Car schema aligns
    car = schemas["Car"]
    @test car["type"] == "object"
    @test car["properties"]["name"]["required"] == true
    @test car["properties"]["name"]["type"] == "string"

    # ensure the generated Person schema aligns
    person = schemas["Person"]
    @test person["type"] == "object"
    @test person["properties"]["name"]["required"] == true
    @test person["properties"]["name"]["type"] == "string"
    @test person["properties"]["car"]["\$ref"] == "#/components/schemas/Car"

    # ensure the generated Party schema aligns
    party = schemas["Party"]
    @test party["type"] == "object"
    @test party["properties"]["guests"]["required"] == true
    @test party["properties"]["guests"]["type"] == "array"
    @test party["properties"]["guests"]["items"]["\$ref"] == "#/components/schemas/Person"

end

end