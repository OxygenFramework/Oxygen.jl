module AutoDocTests

import HTTP

using Test
using Dates
using Oxygen; @oxidize
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

@kwdef struct MyRequest
    name::String
    max_items::Union{Nothing, Int} = nothing
    tags::Union{Nothing, Vector{String}} = nothing
end

@kwdef struct Fleet
    vehicles::Dict{String,Car} = Dict{String,Car}()
    counts::Dict{String,Vector{Int}} = Dict{String,Vector{Int}}()
end

@kwdef struct Paddock
    animals::Vector{Union{Car,Person,Nothing}} = Vector{Union{Car,Person,Nothing}}()
    maybe::Vector{Union{Car,Nothing}} = Vector{Union{Car,Nothing}}()
end

@enum ResponseKind::Int64 response_kind_a response_kind_b

struct ResponseMeta
    source::String
    tag::Symbol
end

struct ResponseItem
    id::Int
    meta::ResponseMeta
end

struct ResponseEnvelope
    item::ResponseItem
    items::Vector{ResponseItem}
    index::Dict{String,ResponseItem}
    maybe::Union{ResponseItem,Nothing}
end

@post "/test-nullable" function(req, body::Json{MyRequest})
    return body.payload
end

@post "/album" function (req, album::Json{Album})
    return album.payload;
end

@post "/album2" function (req, album::Json{Album})
    return album.payload;
end

@post "/fleet" function(req, fleet::Json{Fleet})
    return fleet.payload
end

@post "/paddock" function(req, paddock::Json{Paddock})
    return paddock.payload
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

    # ensure dictionary fields describe their value type
    fleet = schemas["Fleet"]
    @test fleet["properties"]["vehicles"]["type"] == "object"
    @test fleet["properties"]["vehicles"]["additionalProperties"]["\$ref"] == "#/components/schemas/Car"
    @test fleet["properties"]["vehicles"]["default"] == Dict{String,Car}()
    @test fleet["properties"]["counts"]["additionalProperties"]["type"] == "array"
    @test fleet["properties"]["counts"]["additionalProperties"]["items"]["type"] == "integer"

    # nullable and heterogeneous union element schemas
    paddock = schemas["Paddock"]
    @test paddock["properties"]["maybe"]["items"]["\$ref"] == "#/components/schemas/Car"
    @test paddock["properties"]["maybe"]["items"]["nullable"] == true
    animals = paddock["properties"]["animals"]["items"]
    @test animals["nullable"] == true
    @test Set(ref["\$ref"] for ref in animals["anyOf"]) ==
          Set(["#/components/schemas/Car", "#/components/schemas/Person"])

    # ensure the generated Party schema aligns
    party = schemas["Party"]
    # There should be no required key defined if no fields are required
    @test !haskey(party, "required")
    @test party["type"] == "object"
    @test party["properties"]["guests"]["type"] == "array"
    @test party["properties"]["guests"]["items"]["\$ref"] == "#/components/schemas/Person"
    @test party["properties"]["guests"]["default"] == [Person("Alice", Car("Toyota")), Person("Bob", Car("Honda"))]
    
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

    @post "/form-test" function(req, data::Oxygen.Form{EnumTopLevel})
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

@testset "nullable primitive and array tests" begin


    ctx = CONTEXT[]
    schemas = ctx.docs.schema["components"]["schemas"]

    @test haskey(schemas, "MyRequest")
    myreq = schemas["MyRequest"]

    @test haskey(myreq["properties"]["max_items"], "nullable")
    @test myreq["properties"]["max_items"]["nullable"] == true
    @test myreq["properties"]["max_items"]["default"] === nothing

    @test haskey(myreq["properties"]["tags"], "nullable")
    @test myreq["properties"]["tags"]["nullable"] == true
    @test myreq["properties"]["tags"]["type"] == "array"
    @test myreq["properties"]["tags"]["items"]["type"] == "string"
    @test myreq["properties"]["tags"]["default"] === nothing

end


@testset "recursive struct tests" begin
    # Example 1: Tree structure with recursive children
    struct TreeNode
        value::String
        children::Vector{TreeNode}
    end

    # Example 2: Person with family relationships (recursive)
    struct PersonRecursive
        name::String
        parent::Union{PersonRecursive, Nothing}
        children::Vector{PersonRecursive}
    end

    # Example 3: Linked list structure
    struct LinkedListNode
        data::Int
        next::Union{LinkedListNode, Nothing}
    end

    # Routes to test recursive schema generation
    @post "/tree-node" function(req, node::Json{TreeNode})
        return node.payload
    end

    @post "/person-recursive" function(req, person::Json{PersonRecursive})
        return person.payload
    end

    @post "/linked-list" function(req, list::Json{LinkedListNode})
        return list.payload
    end

        # Update context to get latest schemas
    ctx = CONTEXT[]
    schemas = ctx.docs.schema["components"]["schemas"]

    # Test that recursive schemas are generated correctly
    @test haskey(schemas, "TreeNode")
    tree_node_schema = schemas["TreeNode"]
    @test tree_node_schema["type"] == "object"
    @test haskey(tree_node_schema["properties"], "children")
    @test tree_node_schema["properties"]["children"]["type"] == "array"
    @test tree_node_schema["properties"]["children"]["items"]["\$ref"] == "#/components/schemas/TreeNode"

    @test haskey(schemas, "PersonRecursive")
    person_schema = schemas["PersonRecursive"]
    @test person_schema["type"] == "object"
    @test person_schema["properties"]["parent"]["\$ref"] == "#/components/schemas/PersonRecursive"
    @test person_schema["properties"]["parent"]["nullable"] == true
    @test person_schema["properties"]["children"]["type"] == "array"
    @test person_schema["properties"]["children"]["items"]["\$ref"] == "#/components/schemas/PersonRecursive"

    @test haskey(schemas, "LinkedListNode")
    list_schema = schemas["LinkedListNode"]
    @test list_schema["type"] == "object"
    @test list_schema["properties"]["next"]["\$ref"] == "#/components/schemas/LinkedListNode"
    @test list_schema["properties"]["next"]["nullable"] == true

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
    @get "/unique-types/{a}/{b}/{c}/{d}/{e}/{f}" function(req, a::Char, b::Real, c::Symbol, d::TestEnum2, e::Regex, f::Float64)
        return (a,b,c,d,e,f)
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

    serve(port=PORT, host=HOST, async=true, show_errors=false, show_banner=false, access_log=nothing)

    # query metrics endpoints
    r = internalrequest(HTTP.Request("GET", "/unique-types/c/0.23/:hello/0/test.*/42.4"), metrics=false)
    @test r.status == 200

    terminate()
end

@testset "unwrap_type hardening" begin
    AutoDoc = Oxygen.Core.AutoDoc

    # `.body` of a bare UnionAll carries free type variables (e.g.
    # `Vector.body` is `Array{T,1}`). Unwrapping those produces malformed types
    # that trip Julia's static-parameter matching (JuliaLang/julia#61242), so
    # they must be left wrapped.
    @test AutoDoc.unwrap_type(Vector) === Vector
    @test AutoDoc.unwrap_type(Dict) === Dict
    @test AutoDoc.unwrap_type(HTTP.Response) === HTTP.Response
    @test AutoDoc.unwrap_type(Vector{<:Integer}) isa UnionAll

    # well-formed parametric types are still returned unchanged
    @test AutoDoc.unwrap_type(Vector{Int}) === Vector{Int}
    @test AutoDoc.unwrap_type(String) === String

    # schema generation must not throw for a bare UnionAll return type
    docs = Oxygen.Core.AppContext.Documenation()
    @test begin
        AutoDoc.registerschema(docs, "/readyz", "GET", [], [], [], [], Any[HTTP.Response])
        true
    end
end

@testset "response schema generation" begin
    AutoDoc = Oxygen.Core.AutoDoc
    Doc = Oxygen.Core.AppContext.Documenation

    function buildresponse(rt)
        docs = Doc()
        AutoDoc.registerschema(docs, "/probe", "GET", [], [], [], [], Any[rt])
        response = docs.schema["paths"]["/probe"]["get"]["responses"]["200"]
        content = haskey(response, "content") ? response["content"] : nothing
        return content, docs
    end

    getresponse(rt) = buildresponse(rt)[1]
    getschema(rt) = getresponse(rt)["application/json"]["schema"]

    @testset "primitive return types" begin
        @test getschema(Bool) == Dict("type" => "boolean")
        @test getschema(Int) == Dict("type" => "integer", "format" => "int64")
        @test getschema(Int32) == Dict("type" => "integer", "format" => "int32")
        @test getschema(Float64) == Dict("type" => "number", "format" => "double")
        @test getschema(Float32) == Dict("type" => "number", "format" => "float")
        @test getschema(Real) == Dict("type" => "number", "format" => "double")
        @test getschema(String) == Dict("type" => "string")
        @test getschema(Char) == Dict("type" => "string")
        @test getschema(Symbol) == Dict("type" => "string")
        @test getschema(ComplexF64)["type"] == "string"
        @test getschema(Date) == Dict("type" => "string", "format" => "date")

        datetime = getschema(DateTime)
        @test datetime["type"] == "string"
        @test datetime["format"] == "date-time"
        @test haskey(datetime, "example")
        @test haskey(datetime, "description")
    end

    @testset "enum return types" begin
        schema = getschema(ResponseKind)
        @test schema["type"] == "integer"
        @test schema["format"] == "int64"
        @test schema["enum"] == [0, 1]

        schema = getschema(Vector{ResponseKind})
        @test schema["type"] == "array"
        @test schema["items"]["enum"] == [0, 1]
    end

    @testset "collection return types" begin
        schema = getschema(Vector{Int})
        @test schema["type"] == "array"
        @test schema["items"] == Dict("type" => "integer", "format" => "int64")

        # nested collections recurse
        schema = getschema(Vector{Vector{Int}})
        @test schema["type"] == "array"
        @test schema["items"]["type"] == "array"
        @test schema["items"]["items"] == Dict("type" => "integer", "format" => "int64")

        # dictionaries describe their value type
        schema = getschema(Dict{String,Int})
        @test schema["type"] == "object"
        @test schema["additionalProperties"] == Dict("type" => "integer", "format" => "int64")

        # bare UnionAll is an unconstrained array, not an error
        @test getschema(Vector) == Dict("type" => "array")
    end

    @testset "nested custom structs recurse" begin
        content, docs = buildresponse(ResponseEnvelope)
        @test content["application/json"]["schema"]["\$ref"] == "#/components/schemas/ResponseEnvelope"

        schemas = docs.schema["components"]["schemas"]
        @test haskey(schemas, "ResponseEnvelope")
        @test haskey(schemas, "ResponseItem")
        @test haskey(schemas, "ResponseMeta")

        envelope = schemas["ResponseEnvelope"]["properties"]
        @test envelope["item"]["\$ref"] == "#/components/schemas/ResponseItem"
        @test envelope["items"]["type"] == "array"
        @test envelope["items"]["items"]["\$ref"] == "#/components/schemas/ResponseItem"
        @test envelope["index"]["additionalProperties"]["\$ref"] == "#/components/schemas/ResponseItem"
        @test envelope["maybe"]["\$ref"] == "#/components/schemas/ResponseItem"
        @test envelope["maybe"]["nullable"] == true

        # recursion goes all the way down
        @test schemas["ResponseItem"]["properties"]["meta"]["\$ref"] == "#/components/schemas/ResponseMeta"
        # Symbol fields serialize as JSON strings
        @test schemas["ResponseMeta"]["properties"]["tag"]["type"] == "string"

        # collections of custom structs also register their components
        @test getschema(Vector{ResponseItem})["items"]["\$ref"] == "#/components/schemas/ResponseItem"
        @test getschema(Dict{String,ResponseItem})["additionalProperties"]["\$ref"] == "#/components/schemas/ResponseItem"
    end

    @testset "union and edge-case return types" begin
        # A function returning `nothing` still advertises a JSON null payload
        @test getresponse(Nothing)["application/json"]["schema"] == Dict("type" => "null")

        # Bottom type is also a JSON null payload
        @test getresponse(Union{})["application/json"]["schema"] == Dict("type" => "null")

        # Unconstrained inference emits no content
        @test getresponse(Any) === nothing

        # Multiple inferred return types become an anyOf collection
        anyof = getresponse(Union{Int, String})["application/json"]["schema"]["anyOf"]
        @test Set(s["type"] for s in anyof) == Set(["integer", "string"])

        # Nullable unions keep the concrete type and mark it nullable
        schema = getresponse(Union{Int, Nothing})["application/json"]["schema"]
        @test schema["type"] == "integer"
        @test schema["nullable"] == true

        # Generic HTTP responses (from text()/html()) have no inferable payload
        @test getresponse(HTTP.Response) === nothing
    end
end

end