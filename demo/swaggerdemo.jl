module SwaggerDemo 

using TimeZones
include("../src/Oxygen.jl")
using .Oxygen




import .Oxygen.Core.Types: Nullable
import .Oxygen.Core.Util: parseparam
import .Oxygen.Core.AutoDoc: is_custom_struct, gettype, getformat

####################################
# Util parsing overloads           #
####################################

function parseparam(::Type{T}, str::String; escape=true) where {T <: ZonedDateTime}
    return parse(T, escape ? HTTP.unescapeuri(str) : str)
end

####################################
# AutoDoc Overloads                #
####################################

is_custom_struct(::Type{ZonedDateTime}) :: Bool = false
gettype(::Type{ZonedDateTime}) :: String = "string"
getformat(::Type{ZonedDateTime}) :: Nullable{String} = "date-time"


using HTTP
using SwaggerMarkdown
using StructTypes
using JSON3
using Dates


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

@post "/party-invite" function(req, party::Json{PartyInvite})
    return text("added $(length(party.payload.guests)) guests")
end

# This will do a recursive dive on the 'Party' type and generate the schema for all structs
@post "/invite-all" function(req, party::Json{Party})
    return text("added $(length(party.payload.guests)) guests")
end


# @enum Fruit apple=1 orange=2 kiwi=3

# struct Person 
#   name  :: String 
#   age   :: Int8
# end

# struct Classroom 
#   name  :: String 
#   people   :: Array{Person}
# end

# struct School
#   name :: String
#   classes :: Array{Classroom}
# end

# Add a supporting struct type definition to the Person struct
# StructTypes.StructType(::Type{Person}) = StructTypes.Struct()
# StructTypes.StructType(::Type{Classroom}) = StructTypes.Struct()
# StructTypes.StructType(::Type{School}) = StructTypes.Struct()

StructTypes.StructType(::Type{Complex{Float64}}) = StructTypes.Struct()

# Test using it directly as a path parameter
@post "/time/" function(req, time::Json{ZonedDateTime})
    return "current date: $time" |> text
end

# Test using it directly as a path parameter
@get "/timev2/{time}" function(req, time::ZonedDateTime)
    return time
end


# @post "/person" function(req, person::Json{Person})
#   return person
# end

# @post "/class" function(req, classroom::Json{Classroom})
#   return classroom
# end

# @post "/school" function(req, school::Json{School})
#   return school
# end

# @get "/fruit/{fruit}" function(req, fruit::Fruit)
#   return fruit
# end

# @get "/date/{date}" function(req, date::Date)
#   return date
# end

# @get "/datetime/{datetime}" function(req, datetime::DateTime)
#   return datetime
# end

# @get "/complex/{complex}" function(req, complex::Complex{Float64})
#   return complex
# end

# @get "/list/{list}" function(req, list::Vector{Float32})
#     return list
# end

# @get "/data/{dict}" function(req, dict::Dict{String, Any})
#   return dict
# end

# @get "/tuple/{tuple}" function(req, tuple::Tuple{String, String})
#   return tuple
# end

# @get "/union/{value}" function(req, value::Union{Bool, String, Float64})
#   return value
# end

# @get "/boolean/{bool}" function(req, bool::Bool)
#   return bool
# end


# @get "/float/{float}" function (req::HTTP.Request, float::Float32)
#   return float
# end

# @swagger """
# /divide/{a}/{b}:
#   get:
#     description: Return the value of a / b
#     parameters:
#       - name: a
#         in: path
#         required: true
#         description: this is your value
#         schema:
#           type: number
#           format: double
#     responses:
#       '200':
#         description: Successfully returned an number.
# """
# # demonstrate how to use path params with type definitions
# @get "/divide/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
#     return a / b
# end

# @get "/add/{a}/{b}" function (req::HTTP.Request, a::UInt32, b::Float16)
#   return a + b
# end

# @get "/add/{success}" function (req::HTTP.Request, success::Bool)
#   return success
# end

# @swagger """
# /home:
#   get:
#     description: returns the home endpoint!!
#     responses:
#         "200":
#             description: Returns a string
#         "503":
#             description: something bad happened
# """
# @get "/home" function()
#     "home"
# end

# # the version of the OpenAPI used is required
# openApi_version = "3.0"

# # the info of the API, title and version of the info are required
# info = Dict{String, Any}()
# info["title"] = "My custom api"
# info["version"] = openApi_version

# openApi = OpenAPI(openApi_version, info)
# swagger_document = build(openApi)

# # merge the SwaggerMarkdown schema with the internal schema
# mergeschema(swagger_document)

serve()
# 
end