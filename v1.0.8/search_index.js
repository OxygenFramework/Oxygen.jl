var documenterSearchIndex = {"docs":
[{"location":"api/#Api","page":"Api","title":"Api","text":"","category":"section"},{"location":"api/","page":"Api","title":"Api","text":"Documentation for Oxygen.jl","category":"page"},{"location":"api/#Starting-the-webserver","page":"Api","title":"Starting the webserver","text":"","category":"section"},{"location":"api/","page":"Api","title":"Api","text":"serve\nserveparallel","category":"page"},{"location":"api/#Oxygen.ServerUtil.serve","page":"Api","title":"Oxygen.ServerUtil.serve","text":"serve(; host=\"127.0.0.1\", port=8080, kwargs...)\n\nStart the webserver with the default request handler\n\n\n\n\n\nserve(handler::Function; host=\"127.0.0.1\", port=8080, kwargs...)\n\nStart the webserver with your own custom request handler\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.serveparallel","page":"Api","title":"Oxygen.ServerUtil.serveparallel","text":"serveparallel(; host=\"127.0.0.1\", port=8080, queuesize=1024, kwargs...)\n\nStarts the webserver in streaming mode and spawns n - 1 worker threads to process individual requests. A Channel is used to schedule individual requests in FIFO order. Requests in the channel are then removed & handled by each the worker threads asynchronously. \n\n\n\n\n\nserveparallel(handler::Function; host=\"127.0.0.1\", port=8080, queuesize=1024, kwargs...)\n\nStarts the webserver in streaming mode with your own custom request handler and spawns n - 1 worker  threads to process individual requests. A Channel is used to schedule individual requests in FIFO order.  Requests in the channel are then removed & handled by each the worker threads asynchronously. \n\n\n\n\n\n","category":"function"},{"location":"api/#Routing","page":"Api","title":"Routing","text":"","category":"section"},{"location":"api/","page":"Api","title":"Api","text":"@get(path, func)\n@post(path, func)\n@put(path, func)\n@patch(path, func)\n@delete(path, func)\n@route(methods, path, func)","category":"page"},{"location":"api/#Oxygen.ServerUtil.@get-Tuple{Any, Any}","page":"Api","title":"Oxygen.ServerUtil.@get","text":"@get(path::String, func::Function)\n\nUsed to register a function to a specific endpoint to handle GET requests  \n\n\n\n\n\n","category":"macro"},{"location":"api/#Oxygen.ServerUtil.@post-Tuple{Any, Any}","page":"Api","title":"Oxygen.ServerUtil.@post","text":"@post(path::String, func::Function)\n\nUsed to register a function to a specific endpoint to handle POST requests\n\n\n\n\n\n","category":"macro"},{"location":"api/#Oxygen.ServerUtil.@put-Tuple{Any, Any}","page":"Api","title":"Oxygen.ServerUtil.@put","text":"@put(path::String, func::Function)\n\nUsed to register a function to a specific endpoint to handle PUT requests\n\n\n\n\n\n","category":"macro"},{"location":"api/#Oxygen.ServerUtil.@patch-Tuple{Any, Any}","page":"Api","title":"Oxygen.ServerUtil.@patch","text":"@patch(path::String, func::Function)\n\nUsed to register a function to a specific endpoint to handle PATCH requests\n\n\n\n\n\n","category":"macro"},{"location":"api/#Oxygen.ServerUtil.@delete-Tuple{Any, Any}","page":"Api","title":"Oxygen.ServerUtil.@delete","text":"@delete(path::String, func::Function)\n\nUsed to register a function to a specific endpoint to handle DELETE requests\n\n\n\n\n\n","category":"macro"},{"location":"api/#Oxygen.ServerUtil.@route-Tuple{Any, Any, Any}","page":"Api","title":"Oxygen.ServerUtil.@route","text":"@route(methods::Array{String}, path::String, func::Function)\n\nUsed to register a function to a specific endpoint to handle mulitiple request types\n\n\n\n\n\n","category":"macro"},{"location":"api/#Mounting-Files","page":"Api","title":"Mounting Files","text":"","category":"section"},{"location":"api/","page":"Api","title":"Api","text":"@staticfiles\n@dynamicfiles\nfile","category":"page"},{"location":"api/#Oxygen.ServerUtil.@staticfiles","page":"Api","title":"Oxygen.ServerUtil.@staticfiles","text":"@staticfiles(folder::String, mountdir::String)\n\nMount all files inside the /static folder (or user defined mount point)\n\n\n\n\n\n","category":"macro"},{"location":"api/#Oxygen.ServerUtil.@dynamicfiles","page":"Api","title":"Oxygen.ServerUtil.@dynamicfiles","text":"@dynamicfiles(folder::String, mountdir::String)\n\nMount all files inside the /static folder (or user defined mount point),  but files are re-read on each request\n\n\n\n\n\n","category":"macro"},{"location":"api/#Oxygen.FileUtil.file","page":"Api","title":"Oxygen.FileUtil.file","text":"file(filepath::String)\n\nReads a file as a String\n\n\n\n\n\n","category":"function"},{"location":"api/#Swagger-Docs","page":"Api","title":"Swagger Docs","text":"","category":"section"},{"location":"api/","page":"Api","title":"Api","text":"configdocs\nenabledocs\ndisabledocs\nisdocsenabled\nmergeschema\nsetschema\ngetschema","category":"page"},{"location":"api/#Oxygen.ServerUtil.AutoDoc.configdocs","page":"Api","title":"Oxygen.ServerUtil.AutoDoc.configdocs","text":"configdocs(docs_url::String = \"/docs\", schema_url::String = \"/docs/schema\")\n\nConfigure the default docs and schema endpoints\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.AutoDoc.enabledocs","page":"Api","title":"Oxygen.ServerUtil.AutoDoc.enabledocs","text":"enabledocs()\n\nTells the api to mount the api doc endpoints on startup\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.AutoDoc.disabledocs","page":"Api","title":"Oxygen.ServerUtil.AutoDoc.disabledocs","text":"disabledocs()\n\nTells the api to SKIP mounting the api doc endpoints on startup\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.AutoDoc.isdocsenabled","page":"Api","title":"Oxygen.ServerUtil.AutoDoc.isdocsenabled","text":"isdocsenabled()\n\nReturns true if we should mount the api doc endpoints, false otherwise\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.AutoDoc.mergeschema","page":"Api","title":"Oxygen.ServerUtil.AutoDoc.mergeschema","text":"mergeschema(route::String, customschema::Dict)\n\nMerge the schema of a specific route\n\n\n\n\n\nmergeschema(customschema::Dict)\n\nMerge the top-level autogenerated schema with a custom schema\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.AutoDoc.setschema","page":"Api","title":"Oxygen.ServerUtil.AutoDoc.setschema","text":"setschema(customschema::Dict)\n\nOverwrites the entire internal schema\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.AutoDoc.getschema","page":"Api","title":"Oxygen.ServerUtil.AutoDoc.getschema","text":"getschema()\n\nReturn the current internal schema for this app\n\n\n\n\n\n","category":"function"},{"location":"api/#Helper-functions","page":"Api","title":"Helper functions","text":"","category":"section"},{"location":"api/","page":"Api","title":"Api","text":"queryparams\nhtml\ntext\njson\nbinary","category":"page"},{"location":"api/#Oxygen.Util.queryparams","page":"Api","title":"Oxygen.Util.queryparams","text":"queryparams(request::HTTP.Request)\n\nParse's the query parameters from the Requests URL and return them as a Dict\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.Util.html","page":"Api","title":"Oxygen.Util.html","text":"html(content::String; status::Int, headers::Pair)\n\nA convenience funtion to return a String that should be interpreted as HTML\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.BodyParsers.text","page":"Api","title":"Oxygen.BodyParsers.text","text":"text(request::HTTP.Request)\n\nRead the body of a HTTP.Request as a String\n\n\n\n\n\ntext(response::HTTP.Response)\n\nRead the body of a HTTP.Response as a String\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.BodyParsers.json","page":"Api","title":"Oxygen.BodyParsers.json","text":"json(request::HTTP.Request)\n\nRead the body of a HTTP.Request as JSON\n\n\n\n\n\njson(request::HTTP.Request, classtype)\n\nRead the body of a HTTP.Request as JSON and serialize it into a custom struct\n\n\n\n\n\njson(response::HTTP.Response)\n\nRead the body of a HTTP.Response as JSON \n\n\n\n\n\njson(response::HTTP.Response, classtype)\n\nRead the body of a HTTP.Response as JSON and serialize it into a custom struct\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.BodyParsers.binary","page":"Api","title":"Oxygen.BodyParsers.binary","text":"binary(request::HTTP.Request)\n\nRead the body of a HTTP.Request as a Vector{UInt8}\n\n\n\n\n\n","category":"function"},{"location":"api/#Extra's","page":"Api","title":"Extra's","text":"","category":"section"},{"location":"api/","page":"Api","title":"Api","text":"internalrequest\nterminate()","category":"page"},{"location":"api/#Oxygen.ServerUtil.internalrequest","page":"Api","title":"Oxygen.ServerUtil.internalrequest","text":"internalrequest(request::HTTP.Request)\n\nDirectly call one of our other endpoints registered with the router\n\n\n\n\n\ninternalrequest(request::HTTP.Request, handler::Function)\n\nDirectly call one of our other endpoints registered with the router, using your own Handler function\n\n\n\n\n\n","category":"function"},{"location":"api/#Oxygen.ServerUtil.terminate-Tuple{}","page":"Api","title":"Oxygen.ServerUtil.terminate","text":"terminate()\n\nstops the webserver immediately\n\n\n\n\n\n","category":"method"},{"location":"#Oxygen.jl","page":"Overview","title":"Oxygen.jl","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"<div>\n  </br>\n  <p align=\"center\"><img src=\"oxygen.png\" width=\"20%\"></p>\n  <p align=\"center\">\n    <strong>A breath of fresh air for programming web apps in Julia.</strong>\n  </p>\n  <p align=\"center\">\n    <a href='https://ndortega.github.io/Oxygen.jl/stable/'><img src='https://img.shields.io/badge/docs-stable-blue.svg' alt='documentation stable' /></a>\n    <a href='https://github.com/ndortega/Oxygen.jl/actions/workflows/ci.yml'><img src='https://github.com/ndortega/Oxygen.jl/actions/workflows/ci.yml/badge.svg' alt='Build Status' /></a>\n    <a href='https://codecov.io/gh/ndortega/Oxygen.jl'><img src='https://codecov.io/gh/ndortega/Oxygen.jl/branch/master/graph/badge.svg?token=7GV8X1C98M' alt='Coverage Status' /></a>\n  </p>\n</div>","category":"page"},{"location":"#About","page":"Overview","title":"About","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Oxygen is a micro-framework built on top of the HTTP.jl library.  Breathe easy knowing you can quickly spin up a web server with abstractions you're already familiar with.","category":"page"},{"location":"#Features","page":"Overview","title":"Features","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Straightforward routing (@get, @post, @put, @patch, @delete and @route macros)\nAuto-generated swagger documentation\nOut-of-the-box JSON serialization & deserialization \nType definition support for path parameters\nStatic file hosting\nBuilt-in multithreading support","category":"page"},{"location":"#Installation","page":"Overview","title":"Installation","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"pkg> add Oxygen","category":"page"},{"location":"#Minimalistic-Example","page":"Overview","title":"Minimalistic Example","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Create a web-server with very few lines of code","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\nusing HTTP\n\n@get \"/greet\" function(req::HTTP.Request)\n    return \"hello world!\"\nend\n\n# start the web server\nserve()","category":"page"},{"location":"#Request-handlers","page":"Overview","title":"Request handlers","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Request handlers are just functions, which means there are many valid ways to express them","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Request handlers don't have to be defined where the routes are. They can be imported from other modules and spread across multiple files\nJust like the request handlers, routes can be declared across multiple modules and files","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\n\n@get \"/greet\" function()\n    \"hello world!\"\nend\n\n@get \"/saluer\" () -> begin\n    \"Bonjour le monde!\"\nend\n\n@get \"/saludar\" () -> \"¡Hola Mundo!\"\n@get \"/salutare\" f() = \"ciao mondo!\"\n\n# This function can be declared in another module\nfunction subtract(req, a::Float64, b::Float64)\n  return a - b\nend\n\n# register foreign request handlers like this\n@get \"/subtract/{a}/{b}\" subtract\n\n# start the web server\nserve()","category":"page"},{"location":"#Path-parameters","page":"Overview","title":"Path parameters","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Path parameters are declared with braces and are passed directly to your request handler. ","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\n\n# use path params without type definitions (defaults to Strings)\n@get \"/add/{a}/{b}\" function(req, a, b)\n    return parse(Float64, a) + parse(Float64, b)\nend\n\n# use path params with type definitions (they are automatically converted)\n@get \"/multiply/{a}/{b}\" function(req, a::Float64, b::Float64)\n    return a * b\nend\n\n# The order of the parameters doesn't matter (just the name matters)\n@get \"/subtract/{a}/{b}\" function(req, b::Int64, a::Int64)\n    return a - b\nend\n\n\n# start the web server\nserve()","category":"page"},{"location":"#Additional-Parameter-Type-Support","page":"Overview","title":"Additional Parameter Type Support","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Oxygen supports a lot of different path parameter types outside of  Julia's base primitives. More complex types & structs are automatically parsed  and passed to your request handlers.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"In most cases, Oxygen uses the built-in parse() function to parse incoming parameters.  But when the parameter types start getting more complex (eg. Vector{Int64} or a custom struct), then Oxygen assumes the parameter is a JSON string and uses the JSON3 library  to serialize the parameter into the corresponding type","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Dates\nusing Oxygen\nusing StructTypes\n\n@enum Fruit apple=1 orange=2 kiwi=3\n\nstruct Person \n  name  :: String \n  age   :: Int8\nend\n\n# Add a supporting struct types\nStructTypes.StructType(::Type{Person}) = StructTypes.Struct()\nStructTypes.StructType(::Type{Complex{Float64}}) = StructTypes.Struct()\n\n@get \"/fruit/{fruit}\" function(req, fruit::Fruit)\n  return fruit\nend\n\n@get \"/date/{date}\" function(req, date::Date)\n  return date\nend\n\n@get \"/datetime/{datetime}\" function(req, datetime::DateTime)\n  return datetime\nend\n\n@get \"/complex/{complex}\" function(req, complex::Complex{Float64})\n  return complex\nend\n\n@get \"/list/{list}\" function(req, list::Vector{Float32})\n    return list\nend\n\n@get \"/data/{dict}\" function(req, dict::Dict{String, Any})\n  return dict\nend\n\n@get \"/tuple/{tuple}\" function(req, tuple::Tuple{String, String})\n  return tuple\nend\n\n@get \"/union/{value}\" function(req, value::Union{Bool, String, Float64})\n  return value\nend\n\n@get \"/boolean/{bool}\" function(req, bool::Bool)\n  return bool\nend\n\n@get \"/struct/{person}\" function(req, person::Person)\n  return person\nend\n\n@get \"/float/{float}\" function (req, float::Float32)\n  return float\nend\n\nserve()","category":"page"},{"location":"#Query-parameters","page":"Overview","title":"Query parameters","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Use the queryparams() function to extract and parse parameters from the url","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\nusing HTTP\n\n@get \"/query\" function(req::HTTP.Request)\n    # extract & return the query params from the request object\n    return queryparams(req)\nend\n\n# start the web server\nserve()","category":"page"},{"location":"#Interpolating-variables-into-endpoints","page":"Overview","title":"Interpolating variables into endpoints","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"You can interpolate variables directly into the paths, which makes dynamically registering routes a breeze ","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"(Thanks to @anandijain for the idea)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\n\noperations = Dict(\"add\" => +, \"multiply\" => *)\nfor (pathname, operator) in operations\n    @get \"/$pathname/{a}/{b}\" function (req, a::Float64, b::Float64)\n        return operator(a, b)\n    end\nend\n\n# start the web server\nserve()","category":"page"},{"location":"#Return-JSON","page":"Overview","title":"Return JSON","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"All objects are automatically deserialized into JSON using the JSON3 library","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\nusing HTTP\n\n@get \"/data\" function(req::HTTP.Request)\n    return Dict(\"message\" => \"hello!\", \"value\" => 99.3)\nend\n\n# start the web server\nserve()","category":"page"},{"location":"#Deserialize-and-Serialize-custom-structs","page":"Overview","title":"Deserialize & Serialize custom structs","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Oxygen provides some out-of-the-box serialization & deserialization for most objects but requires the use of StructTypes when converting structs","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\nusing HTTP\nusing StructTypes\n\nstruct Animal\n    id::Int\n    type::String\n    name::String\nend\n\n# Add a supporting struct type definition so JSON3 can serialize & deserialize automatically\nStructTypes.StructType(::Type{Animal}) = StructTypes.Struct()\n\n@get \"/get\" function(req::HTTP.Request)\n    # serialize struct into JSON automatically (because we used StructTypes)\n    return Animal(1, \"cat\", \"whiskers\")\nend\n\n@post \"/echo\" function(req::HTTP.Request)\n    # deserialize JSON from the request body into an Animal struct\n    animal = json(req, Animal)\n    # serialize struct back into JSON automatically (because we used StructTypes)\n    return animal\nend\n\n# start the web server\nserve()","category":"page"},{"location":"#Multithreading-and-Parallelism","page":"Overview","title":"Multithreading & Parallelism","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"For scenarios where you need to handle higher amounts of traffic, you can run Oxygen in a  multithreaded mode. In order to utilize this mode, julia must have more than 1 thread to work with. You can start a julia session with 4 threads using the command below","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"julia --threads 4","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"serveparallel(queuesize=1024) Starts the webserver in streaming mode and spawns n - 1 worker  threads. The queuesize parameter sets how many requests can be scheduled within the queue (a julia Channel) before they start getting dropped. Each worker thread pops requests off the queue and handles them asynchronously within each thread. ","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\nusing StructTypes\nusing Base.Threads\n\n# Make the Atomic struct serializable\nStructTypes.StructType(::Type{Atomic{Int64}}) = StructTypes.Struct()\n\nx = Atomic{Int64}(0);\n\n@get \"/show\" function()\n    return x\nend\n\n@get \"/increment\" function()\n    atomic_add!(x, 1)\n    return x\nend\n\n# start the web server in parallel mode\nserveparallel()","category":"page"},{"location":"#Autogenerated-Docs-with-Swagger","page":"Overview","title":"Autogenerated Docs with Swagger","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Swagger documentation is automatically generated for each route you register in your application. Only the route name, parameter types, and 200 & 500 responses are automatically created for you by default. ","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"You can view your generated documentation at /docs, and the schema can be found under /docs/schema. Both of these values can be changed to whatever you want using the configdocs() function. You can also opt out of autogenerated docs entirely by calling the disabledocs() function  before starting your application. ","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"To add additional details you can either use the built-in mergeschema() or setschema() functions to directly modify the schema yourself or merge the generated schema from the SwaggerMarkdown.jl package (I'd recommend the latter)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Below is an example of how to merge the schema generated from the SwaggerMarkdown.jl package.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\nusing SwaggerMarkdown\n\n# Here's an example of how you can merge autogenerated docs from SwaggerMarkdown.jl into your api\n@swagger \"\"\"\n/divide/{a}/{b}:\n  get:\n    description: Return the result of a / b\n    parameters:\n      - name: a\n        in: path\n        required: true\n        description: this is the value of the numerator \n        schema:\n          type : number\n    responses:\n      '200':\n        description: Successfully returned an number.\n\"\"\"\n@get \"/divide/{a}/{b}\" function (req, a::Float64, b::Float64)\n    return a / b\nend\n\n# title and version are required\ninfo = Dict(\"title\" => \"My Demo Api\", \"version\" => \"1.0.0\")\nopenApi = OpenAPI(\"3.0\", info)\nswagger_document = build(openApi)\n  \n# merge the SwaggerMarkdown schema with the internal schema\nmergeschema(swagger_document)\n\n# start the web server\nserve()","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Below is an example of how to manually modify the schema","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\nusing SwaggerMarkdown\n\n# Only the basic information is parsed from this route when generating docs\n@get \"/multiply/{a}/{b}\" function (req, a::Float64, b::Float64)\n    return a * b\nend\n\n# Here's an example of how to update a part of the schema yourself\nmergeschema(\"/multiply/{a}/{b}\", \n  Dict(\n    \"get\" => Dict(\n      \"description\" => \"return the result of a * b\"\n    )\n  )\n)\n\n# Here's another example of how to update a part of the schema yourself, but this way allows you to modify other properties defined at the root of the schema (title, summary, etc.)\nmergeschema(\n  Dict(\n    \"paths\" => Dict(\n      \"/multiply/{a}/{b}\" => Dict(\n        \"get\" => Dict(\n          \"description\" => \"return the result of a * b\"\n        )\n      )\n    )\n  )\n)","category":"page"},{"location":"#Mounting-Static-Files","page":"Overview","title":"Mounting Static Files","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"You can mount static files using this handy macro which recursively searches a folder for files and mounts everything. All files are  loaded into memory on startup.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\n\n# mount all files inside the \"content\" folder under the \"/static\" path\n@staticfiles \"content\" \"static\"\n\n# start the web server\nserve()","category":"page"},{"location":"#Mounting-Dynamic-Files","page":"Overview","title":"Mounting Dynamic Files","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Similar to @staticfiles, this macro mounts each path and re-reads the file for each request. This means that any changes to the files after the server has started will be displayed.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"using Oxygen\n\n# mount all files inside the \"content\" folder under the \"/dynamic\" path\n@dynamicfiles \"content\" \"dynamic\"\n\n# start the web server\nserve()","category":"page"},{"location":"#Logging","page":"Overview","title":"Logging","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Oxygen provides a default logging format but allows you to customize the format using the access_log parameter. This functionality is available in both  the serve() and serveparallel() functions.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"You can read more about the logging options here","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"# Uses the default logging format\nserve()\n\n# Customize the logging format \nserve(access_log=logfmt\"[$time_iso8601] \\\"$request\\\" $status\")\n\n# Disable internal request logging \nserve(access_log=nothing)","category":"page"},{"location":"#API-Reference-(macros)","page":"Overview","title":"API Reference (macros)","text":"","category":"section"},{"location":"#@get,-@post,-@put,-@patch,-@delete","page":"Overview","title":"@get, @post, @put, @patch, @delete","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  @get(path, func)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\npath string Required. The route to register\nfunc function Required. The request handler for this route","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Used to register a function to a specific endpoint to handle that corresponding type of request","category":"page"},{"location":"#@route","page":"Overview","title":"@route","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  @route(methods, path, func)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\nmethods array Required. The types of HTTP requests to register to this route\npath string Required. The route to register\nfunc function Required. The request handler for this route","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Low-level macro that allows a route to be handle multiple request types","category":"page"},{"location":"#@staticfiles","page":"Overview","title":"@staticfiles","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  @staticfiles(folder, mount)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\nfolder string Required. The folder to serve files from\nmountdir string The root endpoint to mount files under (default is \"static\")","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Serve all static files within a folder. This function recursively searches a directory and mounts all files under the mount directory using their relative paths.","category":"page"},{"location":"#Request-helper-functions","page":"Overview","title":"Request helper functions","text":"","category":"section"},{"location":"#html()","page":"Overview","title":"html()","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  html(content, status, headers)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\ncontent string Required. The string to be returned as HTML\nstatus integer The HTTP response code (default is 200)\nheaders dict The headers for the HTTP response (default has content-type header set to \"text/html; charset=utf-8\")","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Helper function to designate when content should be returned as HTML","category":"page"},{"location":"#queryparams()","page":"Overview","title":"queryparams()","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  queryparams(request)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\nreq HTTP.Request Required. The HTTP request object","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Returns the query parameters from a request as a Dict()","category":"page"},{"location":"#Body-Functions","page":"Overview","title":"Body Functions","text":"","category":"section"},{"location":"#text()","page":"Overview","title":"text()","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  text(request)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\nreq HTTP.Request Required. The HTTP request object","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Returns the body of a request as a string","category":"page"},{"location":"#binary()","page":"Overview","title":"binary()","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  binary(request)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\nreq HTTP.Request Required. The HTTP request object","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Returns the body of a request as a binary file (returns a vector of UInt8s)","category":"page"},{"location":"#json()","page":"Overview","title":"json()","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"  json(request, classtype)","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Parameter Type Description\nreq HTTP.Request Required. The HTTP request object\nclasstype struct A struct to deserialize a JSON object into","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Deserialize the body of a request into a julia struct ","category":"page"}]
}
