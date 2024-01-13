module RunTests 
using Test
using HTTP
using JSON3
using StructTypes
using Sockets
using Dates 

ENV["OXYGEN_TESTING_MODE"] = "true"

include("../src/Oxygen.jl")
using .Oxygen

include("metricstests.jl")
include("templatingtests.jl")
include("routingfunctionstests.jl")
include("bodyparsertests.jl")
include("crontests.jl")


struct Person
    name::String
    age::Int
end

struct Book
    name::String
    author::String
end

localhost = "http://127.0.0.1:8080"

configdocs("/docs", "/schema")

StructTypes.StructType(::Type{Person}) = StructTypes.Struct()

# mount all files inside the content folder under /static
@staticfiles "content"

# mount files under /dynamic
@dynamicfiles "content" "/dynamic"

@get "/killserver" function ()
    terminate()
end

@get "/anonymous" function()
    return "no args"
end

@get "/test" function(req)
    return "hello world!"
end

@get "/testredirect" function(req)
    return redirect("/test")
end

@get "/customerror" function ()
    function processtring(input::String)
        "<$input>"
    end
    processtring(3)
end

@get "/data" function ()
    return Dict("message" => "hello world")
end

@get "/undefinederror" function ()
    asdf
end

@get "/unsupported-struct" function ()
    return Book("mobdy dick", "blah")
end

try 
    @get "/mismatched-params/{a}/{b}" function (a,c)
        return "$a, $c"
    end
catch e
    @test true 
end

@get "/add/{a}/{b}" function (req, a::Int32, b::Int64)
    return a + b
end

@get "/divide/{a}/{b}" function (req, a, b)
    return parse(Float64, a) / parse(Float64, b)
end

# path is missing function parameter
try 
    @get "/mismatched-params/{a}/{b}" function (req, a,b,c)
        return "$a, $b, $c"
    end
catch e
    @test true
end

# request handler is missing a parameter
try 
    @get "/mismatched-params/{a}/{b}" function (req, a)
        return "$a, $b, $c"
    end
catch e
    @test true 
end

@get "/file" function(req)
    return file("content/sample.html")
end

@get "/multiply/{a}/{b}" function(req, a::Float64, b::Float64)
    return a * b 
end

@get "/person" function(req)
    return Person("joe", 20)
end 

@get "/text" function(req)
    return text(req)
end 

@get "/binary" function(req)
    return binary(req)
end 

@get "/json" function(req)
    return json(req)
end 

@get "/person-json" function(req)
    return json(req, Person)
end 

@get "/html" function(req)
    return html(""" 
        <!DOCTYPE html>
            <html>
            <body> 
                <h1>hello world</h1>
            </body>
        </html>
    """)
end 

@route ["GET"] "/get" function(req)
    return "get"
end 

@get "/query" function(req)
    return queryparams(req)
end 

@post "/post" function(req)
    return text(req)
end 

@put "/put" function(req)
    return "put"
end 

@patch "/patch" function(req)
    return "patch"
end 

@delete "/delete" function(req)
    return "delete"
end 



@enum Fruit apple=1 orange=2 kiwi=3
struct Student 
  name  :: String 
  age   :: Int8
end

StructTypes.StructType(::Type{Student}) = StructTypes.Struct()
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

@get "/dict/{dict}" function(req, dict::Dict{String, Any})
  return dict
end

@get "/tuple/{tuple}" function(req, tuple::Tuple{String, String})
  return tuple
end

@get "/union/{value}" function(req, value::Union{Bool, String})
  return value
end

@get "/boolean/{bool}" function(req, bool::Bool)
  return bool
end

@get "/struct/{student}" function(req, student::Student)
  return student
end

@get "/float/{float}" function (req, float::Float32)
  return float
end

routerdict = Dict("value" => 0)
repeat = router("/repeat", interval = 0.5, tags=["repeat"])

@get "/getroutervalue" function(req)
    return routerdict["value"]
end

@get repeat("/increment", tags=["increment"]) function(req)
    routerdict["value"] += 1
    return routerdict["value"]
end

function middleware1(handler)
    return function(req::HTTP.Request)
        handler(req)
    end
end

function middleware2(handler)
    return function(req::HTTP.Request)
        handler(req)
    end
end

function middleware3(handler)
    return function(req::HTTP.Request)
        handler(req)
    end
end

function middleware4(handler)
    return function(req::HTTP.Request)
        handler(req)
    end
end

# case 1: no middleware setup,  uses the global middleware by default
@get "/math/add/{a}/{b}" function (req::HTTP.Request, a::Float64, b::Float64)
    return a + b
end

# case 1: no middleware is defined at any level -> use global middleware
@get router("/math/power/{a}/{b}") function (req::HTTP.Request, a::Float64, b::Float64)
    return a ^ b
end

math = router("/math", middleware=[middleware3])

# case 2: middleware is cleared at route level so don't register any middleware
@get math("/cube/{a}", middleware=[]) function(req, a::Float64)
    return a * a * a
end

# case 3: router-level is empty & route-level is defined
other = router("/math", middleware=[])
@get other("/multiply/{a}/{b}", middleware=[middleware3]) function (req::HTTP.Request, a::Float64, b::Float64)
    return a * b
end
# case 4 (both defined)
@get math("/divide/{a}/{b}", middleware=[middleware4]) function(req::HTTP.Request, a::Float64, b::Float64)
    return a / b
end

# case 5: only router level is defined
@get math("/subtract/{a}/{b}") function(req::HTTP.Request, a::Float64, b::Float64)
    return a - b
end

# case 6: only route level middleware is defined
empty = router()
@get empty("/math/square/{a}", middleware=[middleware3]) function(req, a::Float64)
    return a * a
end

emptyrouter = router()
@get router("emptyrouter") function(req)
    return "emptyrouter"
end

emptysubpath = router("/emptysubpath", tags=["empty"])
@get emptysubpath("", middleware=[middleware1]) function(req)
    return "emptysubpath"
end

# added another request hanlder for post requests on the same route
@post emptysubpath("") function(req)
    return "emptysubpath - post"
end

serve(async=true)

# query metrics endpoints
r = internalrequest(HTTP.Request("GET", "/docs/metrics/data/15/null"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/anonymous"))
@test r.status == 200
@test text(r) == "no args"

r = internalrequest(HTTP.Request("GET", "/fake-endpoint"))
@test r.status == 404

r = internalrequest(HTTP.Request("GET", "/test"))
@test r.status == 200
@test text(r) == "hello world!"

r = internalrequest(HTTP.Request("GET", "/testredirect"))
@test r.status == 307
@test Dict(r.headers)["Location"] == "/test"

r = internalrequest(HTTP.Request("GET", "/multiply/5/8"))
@test r.status == 200
@test text(r) == "40.0"

r = internalrequest(HTTP.Request("GET", "/person"))
@test r.status == 200
@test json(r, Person) == Person("joe", 20)

r = internalrequest(HTTP.Request("GET", "/html"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "text/html; charset=utf-8"



# path param tests 

# boolean
r = internalrequest(HTTP.Request("GET", "/boolean/true"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/boolean/false"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/boolean/asdf"))
@test r.status == 500


# enums
r = internalrequest(HTTP.Request("GET", "/fruit/1"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/fruit/4"))
@test r.status == 500

r = internalrequest(HTTP.Request("GET", "/fruit/-3"))
@test r.status == 500

# date
r = internalrequest(HTTP.Request("GET", "/date/2022"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/date/2022-01-01"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/date/-3"))
@test r.status == 500

# datetime

r = internalrequest(HTTP.Request("GET", "/datetime/2022-01-01"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/datetime/2022"))
@test r.status == 500

r = internalrequest(HTTP.Request("GET", "/datetime/-3"))
@test r.status == 500


# complex
r = internalrequest(HTTP.Request("GET", "/complex/3.2e-1"))
@test r.status == 200

# list 
r = internalrequest(HTTP.Request("GET", "/list/[1,2,3]"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/list/[]"))
@test r.status == 200

# dictionary 
r = internalrequest(HTTP.Request("GET", """/dict/{"msg": "hello world"}"""))
@test r.status == 200
@test json(r)["msg"] == "hello world"

r = internalrequest(HTTP.Request("GET", "/dict/{}"))
@test r.status == 200

# tuple 
r = internalrequest(HTTP.Request("GET", """/tuple/["a","b"]"""))
@test r.status == 200
@test text(r) == """["a","b"]"""

r = internalrequest(HTTP.Request("GET", """/tuple/["a","b","c"]"""))
@test r.status == 200
@test text(r) == """["a","b"]"""

# union 
r = internalrequest(HTTP.Request("GET", "/union/true"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "application/json; charset=utf-8"

r = internalrequest(HTTP.Request("GET", "/union/false"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "application/json; charset=utf-8"

r = internalrequest(HTTP.Request("GET", "/union/asdfasd"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "text/plain; charset=utf-8"

# struct 
r = internalrequest(HTTP.Request("GET", """/struct/{"name": "jim", "age": 20}"""))
@test r.status == 200
@test json(r, Student) == Student("jim", 20)

r = internalrequest(HTTP.Request("GET", """/struct/{"aged": 20}"""))
@test r.status == 500

r = internalrequest(HTTP.Request("GET", """/struct/{"aged": 20}"""))
@test r.status == 500

# float 
r = internalrequest(HTTP.Request("GET", "/float/3.5"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/float/3"))
@test r.status == 200

# GET, PUT, POST, PATCH, DELETE, route macro tests 

r = internalrequest(HTTP.Request("GET", "/get"))
@test r.status == 200
@test text(r) == "get"

r = internalrequest(HTTP.Request("POST", "/post", [], "this is some data"))
@test r.status == 200
@test text(r) == "this is some data"

r = internalrequest(HTTP.Request("PUT", "/put"))
@test r.status == 200
@test text(r) == "put"

r = internalrequest(HTTP.Request("PATCH", "/patch"))
@test r.status == 200
@test text(r) == "patch"


# Query params tests 

r = internalrequest(HTTP.Request("GET", "/query?message=hello"))
@test r.status == 200
@test json(r)["message"] == "hello"

r = internalrequest(HTTP.Request("GET", "/query?message=hello&value=5"))
data = json(r)
@test r.status == 200
@test data["message"] == "hello"
@test data["value"] == "5"

# Get mounted static files

r = internalrequest(HTTP.Request("GET", "/static/test.txt"))
body = text(r)
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "text/plain; charset=utf-8"
@test body == file("content/test.txt")
@test body == "this is a sample text file"

r = internalrequest(HTTP.Request("GET", "/static/sample.html"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "text/html; charset=utf-8"
@test text(r) == file("content/sample.html")

r = internalrequest(HTTP.Request("GET", "/static/index.html"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "text/html; charset=utf-8"
@test text(r) == file("content/index.html")

r = internalrequest(HTTP.Request("GET", "/static/"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "text/html; charset=utf-8"
@test text(r) == file("content/index.html")

r = internalrequest(HTTP.Request("GET", "/static/"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "text/html; charset=utf-8"
@test text(r) == file("content/index.html")

# Body transformation tests

r = internalrequest(HTTP.Request("GET", "/text", [], "hello there!"))
@test r.status == 200
@test text(r) == "hello there!"

r = internalrequest(HTTP.Request("GET", "/binary", [], "hello there!"))
@test r.status == 200
@test String(r.body) == "[104,101,108,108,111,32,116,104,101,114,101,33]"

r = internalrequest(HTTP.Request("GET", "/json", [], "{\"message\": \"hi\"}"))
@test r.status == 200
@test json(r)["message"] == "hi"

r = internalrequest(HTTP.Request("GET", "/person"))
person = json(r, Person)
@test r.status == 200
@test person.name == "joe"
@test person.age == 20

r = internalrequest(HTTP.Request("GET", "/person-json", [], "{\"name\":\"jim\",\"age\":25}"))
person = json(r, Person)
@test r.status == 200
@test person.name == "jim"
@test person.age == 25

r = internalrequest(HTTP.Request("GET", "/file"))
@test r.status == 200
@test text(r) == file("content/sample.html")

r = internalrequest(HTTP.Request("GET", "/dynamic/sample.html"))
@test r.status == 200
@test text(r) == file("content/sample.html")

r = internalrequest(HTTP.Request("GET", "/static/sample.html"))
@test r.status == 200
@test text(r) == file("content/sample.html")

r = internalrequest(HTTP.Request("GET", "/multiply/a/8"))
@test r.status == 500

# don't suppress error reporting for this test
r = internalrequest(HTTP.Request("GET", "/multiply/a/8"))
@test r.status == 500

# hit endpoint that doesn't exist
r = internalrequest(HTTP.Request("GET", "asdfasdf"))
@test r.status == 404

r = internalrequest(HTTP.Request("GET", "asdfasdf"))
@test r.status == 404

r = internalrequest(HTTP.Request("GET", "/somefakeendpoint"))
@test r.status == 404

r = internalrequest(HTTP.Request("GET", "/customerror"))
@test r.status == 500

r = internalrequest(HTTP.Request("GET", "/undefinederror"))
@test r.status == 500    


try 
    # apparently you don't need to have StructTypes setup on a custom type with the latest JSON3 library
    r = internalrequest(HTTP.Request("GET", "/unsupported-struct"))
catch e 
    @test e isa ArgumentError
end

## docs related tests 

# should be set to true by default
@test isdocsenabled() == true 

disabledocs()
@test isdocsenabled() == false 

enabledocs()
@test isdocsenabled() == true 

terminate()
enabledocs()
@async serve(docs=true)
sleep(5)

## Router related tests

# case 1
r = internalrequest(HTTP.Request("GET", "/math/add/6/5"))
@test r.status == 200
@test text(r) == "11.0"

# case 1
r = internalrequest(HTTP.Request("GET", "/math/power/6/5"))
@test r.status == 200
@test text(r) == "7776.0"

# case 2
r = internalrequest(HTTP.Request("GET", "/math/cube/3"))
@test r.status == 200
@test text(r) == "27.0"

# case 3
r = internalrequest(HTTP.Request("GET", "/math/multiply/3/5"))
@test r.status == 200
@test text(r) == "15.0"

# case 4
r = internalrequest(HTTP.Request("GET", "/math/divide/3/5"))
@test r.status == 200
@test text(r) == "0.6"

# case 5
r = internalrequest(HTTP.Request("GET", "/math/subtract/3/5"))
@test r.status == 200
@test text(r) == "-2.0"

# case 6
r = internalrequest(HTTP.Request("GET", "/math/square/3"))
@test r.status == 200
@test text(r) == "9.0"

r = internalrequest(HTTP.Request("GET", "/getroutervalue"))
@test r.status == 200
@test parse(Int64, text(r)) > 0

r = internalrequest(HTTP.Request("GET", "/emptyrouter"))
@test r.status == 200
@test text(r) == "emptyrouter"

r = internalrequest(HTTP.Request("GET", "/emptysubpath"))
@test r.status == 200
@test text(r) == "emptysubpath"

r = internalrequest(HTTP.Request("POST", "/emptysubpath"))
@test r.status == 200
@test text(r) == "emptysubpath - post"

# kill any background tasks still running
stoptasks()

## internal docs and metrics tests

r = internalrequest(HTTP.Request("GET", "/get"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/docs"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/docs/swagger"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/docs/redoc"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/docs/schema"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/docs/metrics"))
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/docs/metrics/data/15/null"))
@test r.status == 200

invocation = []

function handler1(handler)
    return function(req::HTTP.Request)
        push!(invocation, 1)
        handler(req)
    end
end

function handler2(handler)
    return function(req::HTTP.Request)
        push!(invocation, 2)
        handler(req)
    end
end

function handler3(handler)
    return function(req::HTTP.Request)
        push!(invocation, 3)
        handler(req)
    end
end

r = internalrequest(HTTP.Request("GET", "/multiply/3/6"), middleware=[handler1, handler2, handler3])
@test r.status == 200
@test invocation == [1,2,3] # enusre the handlers are called in the correct order
@test text(r) == "18.0" 

r = internalrequest(HTTP.Request("GET", "/docs"), middleware=[handler1])
@test r.status == 200

r = internalrequest(HTTP.Request("GET", "/docs/schema"))
@test r.status == 200
@test Dict(r.headers)["Content-Type"] == "application/json; charset=utf-8"

# test emtpy dict (which should be skipped)
mergeschema(Dict(
    "paths" => Dict(
        "/multiply/{a}/{b}" => Dict(
            "get" => Dict(
                "description" => "returns the result of a * b",
                "parameters" => [
                    Dict()
                ]
            )
        )
    )
))


mergeschema(Dict(
    "paths" => Dict(
        "/multiply/{a}/{b}" => Dict(
            "get" => Dict(
                "description" => "returns the result of a * b",
                "parameters" => [
                    Dict(
                        "name" => "a",
                        "in" => "path",
                        "required" => "true",
                        "schema" => Dict(
                            "type" => "number"
                        )
                    ),
                    Dict(
                        "name" => "b",
                        "in" => "path",
                        "required" => "true",
                        "schema" => Dict(
                            "type" => "number"
                        )
                    )
                ]
            )
        )
    )
))

@assert getschema()["paths"]["/multiply/{a}/{b}"]["get"]["description"] == "returns the result of a * b"

mergeschema("/put", 
    Dict(
        "put" => Dict(
            "description" => "returns a string on PUT",
            "parameters" => []
        )
    )
)

@assert getschema()["paths"]["/put"]["put"]["description"] == "returns a string on PUT"

data = Dict("msg" => "this is not a valid schema dictionary")
setschema(data)

@assert getschema() === data

terminate()

@async serve(middleware=[handler1, handler2, handler3])
sleep(1)

r = internalrequest(HTTP.Request("GET", "/get"))
@test r.status == 200

# redundant terminate() calls should have no affect
terminate()
terminate()
terminate()

function errorcatcher(handle)
    function(req)
        try 
            response = handle(req)
            return response
        catch e 
            return HTTP.Response(500, "here's a custom error response")
        end
    end
end

# Test default handler by turning off serializaiton
@async serve(serialize=false, middleware=[error_catcher], catch_errors=false)
sleep(3)
r = internalrequest(HTTP.Request("GET", "/get"), catch_errors=false)
@test r.status == 200

try 
    # test the error handler inside the default handler
    r = HTTP.get("$localhost/undefinederror"; readtimeout=1)
catch e
    @test true
end

try 
    # service should not have started and get requests should throw some error
    r = HTTP.get("$localhost/data"; readtimeout=1)
catch e
    @test true
finally
    terminate()
end

try 
    # service should not have started and get requests should throw some error
    @async serveparallel()
    sleep(3)
    r = HTTP.get("$localhost/get"; readtimeout=1)
catch e
    @test true
finally
    terminate()
end

# only run these tests if we have more than one thread to work with
if Threads.nthreads() > 1 && VERSION != parse(VersionNumber, "1.6.6")

    @async serveparallel()
    sleep(3)

    r = HTTP.get("$localhost/get")
    @test r.status == 200

    r = HTTP.post("$localhost/post", body="some demo content")
    @test text(r) == "some demo content"

    try
        r = HTTP.get("$localhost/customerror", connect_timeout=3)
    catch e 
        @test e isa MethodError || e isa HTTP.ExceptionRequest.StatusError
    end
    
    terminate()

    @async serveparallel(middleware=[handler1, handler2, handler3])
    sleep(1)

    r = HTTP.get("$localhost/get")
    @test r.status == 200

    terminate()

    try 
        @async serveparallel(queuesize=0)
        sleep(1)
        r = HTTP.get("$localhost/get")
    catch e
        @test e isa HTTP.ExceptionRequest.StatusError
    finally
        terminate()
    end
end

terminate()
resetstate()

end 