module SwaggerDemo 

include("../src/Oxygen.jl")
using .Oxygen
using HTTP
using SwaggerMarkdown

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
          type : number
    responses:
      '200':
        description: Successfully returned an number.
"""
# demonstrate how to use path params with type definitions
@get "/divide/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a / b
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

serve(access_log=nothing)

end