module AutoDocTests

using Test
using Dates
using Oxygen; @oxidise
using ..Constants
using ..TestUtils

struct Car
    name::String
end

struct Person 
    name::String
    car::Car
end

@kwdef struct Party
    guests::Vector{Person} = [Person("Alice", Car("Toyota")), Person("Bob", Car("Honda"))]
end

struct PartyInvite 
    party::Party
    time::DateTime
end

struct EventInvite 
    party::Party
    times::Vector{DateTime}
end

@kwdef struct Album 
    releaseyear::Int
    artist::Person
    remasteredyear::Union{Int,Nothing}
    soundtech::Union{Person,Nothing}
    collaborators::Union{Vector{Person}, Nothing}
    composer::Union{Person,Nothing} = nothing
end

@post "/album" function (req, album::Json{Album})
    return album.payload;
end

@post "/album2" function (req, album::Json{Album})
    return album.payload;
end

@post "/party-invite" function(req, party::Json{PartyInvite})
    return text("added $(length(party.payload.party.guests)) guests")
end

@post "/event-invite" function(req, event::Json{EventInvite})
    return text("added $(length(event.payload.party.guests)) guests")
end

# This will do a recursive dive on the 'Party' type and generate the schema for all structs
@post "/invite-all" function(req, party::Json{Party})
    return text("added $(length(party.payload.guests)) guests")
end

ctx = CONTEXT[]
schemas = ctx.docs.schema["components"]["schemas"]

@testset "schema merge tests" begin
    obj = Dict("required" => ["field1", "field2"])
    merged = Oxygen.AutoDoc.mergeschema(obj,obj)
    
    # Fix: Test that mergeschema will not duplicate keys in simple vectors 
    @test value_count(obj, "required", "field1") == 1

    obj1 = Dict("required" => ["field1"])
    obj2 = Dict("required" => ["field2"])
    merged = Oxygen.AutoDoc.mergeschema(obj,obj)

    # Test that partial arrays are combined in output
    @test values_present(merged, "required", ["field1", "field2"])

    # When merging primitive vectors choose the latest instead of merging them
    obj = Dict("required" => ["field1","field1","field2"])
    obj = Dict("required" => ["field1","field2","field2"])
    merged = Oxygen.AutoDoc.mergeschema(obj,obj)
    @test value_count(obj, "required", "field1") == 1
    # Verify that merge doesn't remove duplciate entries
    @test value_count(obj, "required", "field2") == 2
end

@testset "schema gen tests" begin 

    # ensure schemas are present for all types
    @test haskey(schemas, "Car")
    @test haskey(schemas, "Person")
    @test haskey(schemas, "Party")
    @test haskey(schemas, "Album")
    
    album = schemas["Album"]
    @test values_present(album, "required", ["releaseyear","artist"])
    # Bug fix: vector of object following object first use missing in 1.7.1
    @test has_property(album, "collaborators")
    # Bug fix: object following initial use missing in 1.7.1
    @test has_property(album, "soundtech")
    # Feature: nullable primitive types should not be required
    @test value_absent(album, "required", "remasteredyear")
    # Nullable vector types should not be required
    @test value_absent(album, "required", "collaborators")
    # Fix: ensure that pararm object referenced in two paths does not clone `required` collection
    @test value_count(album, "required", "artist") == 1

    # ensure the generated Car schema aligns
    car = schemas["Car"]
    @test car["type"] == "object"
    @test values_present(car, "required", ["name"])
    @test car["properties"]["name"]["type"] == "string"

    # ensure the generated Person schema aligns
    person = schemas["Person"]
    @test person["type"] == "object"
    @test values_present(person, "required", ["name", "car"])
    @test person["properties"]["name"]["type"] == "string"
    @test person["properties"]["car"]["\$ref"] == "#/components/schemas/Car"

    # ensure the generated Party schema aligns
    party = schemas["Party"]
    # There should be no required key defined if no fields are required
    @test !haskey(party, "required")
    @test party["type"] == "object"
    @test party["properties"]["guests"]["type"] == "array"
    @test party["properties"]["guests"]["items"]["\$ref"] == "#/components/schemas/Person"
    @test party["properties"]["guests"]["default"] == "[{\"name\":\"Alice\",\"car\":{\"name\":\"Toyota\"}},{\"name\":\"Bob\",\"car\":{\"name\":\"Honda\"}}]"
    
    # ensure the generated PartyInvite schema aligns
    party_invite = schemas["PartyInvite"]
    # Properties without default vaules should be required
    @test party_invite["type"] == "object"
    @test values_present(party_invite, "required", ["party", "time"])
    @test party_invite["properties"]["time"]["type"] == "string"
    @test party_invite["properties"]["time"]["format"] == "date-time"

    # ensure the generated PartyInvite schema aligns
    event_invite = schemas["EventInvite"]
    @test event_invite["type"] == "object"
    @test values_present(event_invite, "required", ["party", "times"])
    @test event_invite["properties"]["times"]["type"] == "array"
    @test event_invite["properties"]["times"]["items"]["format"] == "date-time"
    @test event_invite["properties"]["times"]["items"]["type"] == "string"
    @test event_invite["properties"]["times"]["items"]["example"] |> !isempty

end 

@testset "additional tests" begin

    # Test gettype for number
    @test Oxygen.AutoDoc.gettype(Float64) == "number"
    @test Oxygen.AutoDoc.gettype(Int32) == "integer"

    # Define enums
    @enum Base64Enum val1 val2
    @enum Base8Enum val3 val4

    # Structs
    struct EnumArrayTest
        enums::Vector{Base64Enum}
    end

    struct EnumTopLevel
        enum::Base8Enum
    end

    # Routes
    @post "/enum-array" function(req, data::Json{EnumArrayTest})
        return data.payload
    end

    @post "/enum-top" function(req, data::Json{EnumTopLevel})
        return data.payload
    end

    @post "/form-test" function(req, data::Form{EnumTopLevel})
        return data.payload
    end

    # Update ctx and schemas
    ctx = CONTEXT[]
    schemas = ctx.docs.schema["components"]["schemas"]

    # Tests
    @test haskey(schemas, "EnumArrayTest")
    enum_array = schemas["EnumArrayTest"]
    @test enum_array["properties"]["enums"]["type"] == "array"
    @test haskey(enum_array["properties"]["enums"]["items"], "enum")
    @test enum_array["properties"]["enums"]["items"]["enum"] == [0, 1]  # val1=0, val2=1

    @test haskey(schemas, "EnumTopLevel")
    enum_top = schemas["EnumTopLevel"]
    @test haskey(enum_top["properties"]["enum"], "enum")
    @test enum_top["properties"]["enum"]["enum"] == [0, 1]  # val3=0, val4=1

    # Test the functions
    @test Oxygen.AutoDoc.extract_non_null_type(Union{Nothing, Missing}) == Union{}
    @test Oxygen.AutoDoc.get_element_type(Union{}) == Any

end


@testset "returntype tests" begin
    # Define additional types for testing return types
    @enum TestEnum::Int64 valA valB valC
    @enum TestEnum2::Int8 enumVal1 enumVal2 enumVal3
    
    struct TestStruct
        id::Int
        name::String
    end

    # Routes with different return types to cover all cases

    # 0. Test generating docs for more edge cases
    @post "/unique-types/{a}/{b}/{c}/{d}" function(req, a::Char, b::Real, c::Symbol, d::TestEnum2)
        return (a,b,c,d)
    end

    # 1. Custom struct return type
    @post "/return-struct" function(req)
        return TestStruct(1, "test")
    end

    # 2. Vector of custom struct
    @post "/return-vector-struct" function(req)
        return [TestStruct(1, "test1"), TestStruct(2, "test2")]
    end

    # 3. Vector of primitive (Int)
    @post "/return-vector-int" function(req)
        return [1, 2, 3]
    end

    # 4. Vector of enum
    @post "/return-vector-enum" function(req)
        return [TestEnum.valA, TestEnum.valB]
    end

    # 5. Primitive return type (Int)
    @post "/return-int" function(req)
        return 42
    end

    # 6. Enum return type
    @post "/return-enum" function(req)
        return TestEnum.valA
    end

    # 7. DateTime return type
    @post "/return-datetime" function(req)
        return now()
    end

    # 8. Union{} return type (edge case)
    @post "/return-union-empty" function(req)
        return nothing
    end

end

end