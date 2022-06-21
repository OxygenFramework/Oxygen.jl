module SwaggerDemo 

include("../src/Oxygen.jl")
using .Oxygen

using HTTP
using JSON3
using SwaggerMarkdown

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
info["version"] = "3.0"

openApi = OpenAPI(openApi_version, info)
swagger_document = build(openApi)

# merge the SwaggerMarkdown schema with the internal schema
mergeschema(swagger_document)

# mergeschema(Dict(
#     "paths" => Dict(
#         "/home" => Dict(
#             "get" => Dict(
#                 "description" => "this is the home endpoint"
#             )
#         )
#     )
# ))

# mergeschema("/home", 
#     Dict(
#         "get" => Dict(
#             "description" => "this is the home endpoint!!!!"
#         )
#     )
# )

serve()

end