module SwaggerDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using SwaggerMarkdown
using StructTypes
using JSON3
using Dates

@enum Fruit apple=1 orange=2 kiwi=3

struct Person 
  name  :: String 
  age   :: Int8
end

# Add a supporting struct type definition to the Person struct
StructTypes.StructType(::Type{Person}) = StructTypes.Struct()
StructTypes.StructType(::Type{Complex{Float64}}) = StructTypes.Struct()

@get "/fruit/{fruit}" function(req, fruit::Fruit)
  return fruit
end

@get "/date/{date}" function(req, date::Date)
  return date
end

@get "/datetime/{datetime}" function(req, datetime::DateTime)
  return datetime
end

@get "/complex/{complex}" function(req, complex::Complex{Float64})
  return complex
end

@get "/list/{list}" function(req, list::Vector{Float32})
    return list
end

@get "/data/{dict}" function(req, dict::Dict{String, Any})
  return dict
end

@get "/tuple/{tuple}" function(req, tuple::Tuple{String, String})
  return tuple
end

@get "/union/{value}" function(req, value::Union{Bool, String, Float64 })
  return value
end

@get "/boolean/{bool}" function(req, bool::Bool)
  return bool
end

@get "/person/{person}" function(req, person::Person)
  return person
end

@get "/float/{float}" function (req::HTTP.Request, float::Float32)
  return float
end

@swagger """
/divide/{a}/{b}:
  get:
    description: Return the value of a / b
    parameters:
      - name: a
        in: path
        required: true
        description: this is your value
        schema:
          type: number
          format: double
    responses:
      '200':
        description: Successfully returned an number.
"""
# demonstrate how to use path params with type definitions
@get "/divide/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

@get "/add/{a}/{b}" function (req::HTTP.Request, a::UInt32, b::Float16)
  return a + b
end

@get "/add/{success}" function (req::HTTP.Request, success::Bool)
  return success
end

@swagger """
/home:
  get:
    description: returns the home endpoint!!
    responses:
        "200":
            description: Returns a string
        "503":
            description: something bad happened
"""
@get "/home" function()
    "home"
end

# the version of the OpenAPI used is required
openApi_version = "3.0"

# the info of the API, title and version of the info are required
info = Dict{String, Any}()
info["title"] = "My custom api"
info["version"] = openApi_version

openApi = OpenAPI(openApi_version, info)
swagger_document = build(openApi)

# merge the SwaggerMarkdown schema with the internal schema
mergeschema(swagger_document)

serve()

end