module Main 
    include("../src/Oxygen.jl")
    using .Oxygen

    include("more.jl")
    using .More

    using HTTP
    using JSON3
    using StructTypes
    using SwaggerMarkdown
    using SwagUI

    # struct Animal
    #     id::Int
    #     type::String
    #     name::String
    # end

    # # Add a supporting struct type definition to the Animal struct
    # StructTypes.StructType(::Type{Animal}) = StructTypes.Struct()

    # @get "/" function()
    #     return "home"
    # end

    # @get "/killserver" function ()
    #     terminate()
    # end

    # # add a default handler for unmatched requests
    # @get "*" function () 
    #     return "looks like you hit an endpoint that doesn't exist"
    # end

    # # You can also interpolate variables into the endpoint
    # operations = Dict("add" => +, "multiply" => *)
    # for (pathname, operator) in operations
    #     @get "/$pathname/{a}/{b}" function (req, a::Float64, b::Float64)
    #         return operator(a, b)
    #     end
    # end

    # demonstate how to use path params (without type definitions)
    @get "/power/{a}/{b}" function (req::HTTP.Request, b, a)
        return parse(Float64, a) ^ parse(Float64, b)
    end

    # @swagger """
    # /divide/{a}/{b}:
    #     get:
    #         description: Return the value of a / b           
    #         parameters:
    #             - name: a
    #               in: path
    #               type: number
    #               required: true
    #             - name: b
    #               in: path
    #               type: number
    #               required: true
    #         responses:
    #             '200':
    #                 description: Successfully returned an artist
    # """
    # # demonstrate how to use path params with type definitions
    # @get "/divide/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    #     return a / b
    # end

    # # Return the body of the request as a string
    # @post "/echo-text" function (req::HTTP.Request)
    #     return text(req)
    # end

    # # demonstrates how to serialize JSON into a julia struct 
    # @post "/animal" function (req)
    #     return json(req, Animal)
    # end

    # # Return the body of the request as a JSON object
    # @post "/echo-json" function (req::HTTP.Request)
    #     return json(req)
    # end

    # # You can also return your own customized HTTP.Response object from an endpoint
    # @get "/custom-response" function (req::HTTP.Request)
    #     test_value = 77.8
    #     return HTTP.Response(200, ["Content-Type" => "text/plain"], body = "$test_value")
    # end

    # # Any object retuned from a function will automatically be converted into JSON (by default)
    # @get "/json" function(req::HTTP.Request)
    #     return Dict("message" => "hello world", "animal" => Animal(1, "cat", "whiskers"))
    # end
    
    # # show how to return a file from an endpoint
    # @get "/files" function (req)
    #     return file("demo/main.jl")
    # end

    # # show how to return a string that needs to be interpreted as html
    # @get "/string-as-html" function (req)
    #     message = "Hello World!"
    #     return html("""
    #         <!DOCTYPE html>
    #             <html>
    #             <body> 
    #                 <h1>$message</h1>
    #             </body>
    #         </html>
    #     """)
    # end

    # @swagger """
    # /demo:
    #     get:
    #         description: show how to use the lower level macro to add a route for any type of request
    #         responses:
    #             '200':
    #                 description: Returns an animal.     
    #     post:
    #         description: show how to use the lower level macro to add a route for any type of request
    #         responses:
    #             '200':
    #                 description: Returns an animal.        
    # """
    # @route ["GET", "POST"] "/demo" function(req)
    #     return Animal(1, "cat", "whiskers")
    # end

    # # recursively mount all files inside the demo folder ex.) demo/main.jl => /static/demo/main.jl 
    # @staticfiles "content"
    # @dynamicfiles "content" "dynamic"


    # CORS headers that show what kinds of complex requests are allowed to API
    headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Headers" => "*",
        "Access-Control-Allow-Methods" => "GET, POST"
    ]

    function CorsHandler(req, defaultHandler)
        # return headers on OPTIONS request
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, headers)
        else 
            return defaultHandler(req)
        end
    end

    # # the info of the API, title and version of the info are required
    # info = Dict("title" => "Oxygen.jl demo api", "version" => "1.0.0")
    # openApi = OpenAPI("2.0", info)
    # swagger_document = build(openApi)
    # swagger_html = render_swagger(swagger_document)

    # # setup endpoint to serve swagger documentation
    # @get "/swagger" function()
    #     return html(swagger_html)
    # end

    # start the web server
    serve((req, router, defaultHandler) -> CorsHandler(req, defaultHandler))

end

