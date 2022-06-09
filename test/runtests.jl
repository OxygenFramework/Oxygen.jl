module RunTests 
    using Test
    using HTTP
    using JSON3
    using StructTypes
    using Sockets

    include("../src/Oxygen.jl")
    using .Oxygen

    struct Person
        name::String
        age::Int
    end

    struct Book
        name::String
        author::String
    end

    localhost = "http://127.0.0.1:8080"

    StructTypes.StructType(::Type{Person}) = StructTypes.Struct()

    # mount all files inside the content folder under /static
    @staticfiles "content"

    # mount files under /dynamic
    @dynamicfiles "content" "dynamic"

    @get "/killserver" function ()
        terminate()
    end

    @get "/anonymous" function()
        return "no args"
    end

    @get "/test" function(req)
        return "hello world!"
    end

    @get "/customerror" function ()
        function processtring(input::String)
            "<$input>"
        end
        processtring(3)
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
        @test e isa LoadError 
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
    
    r = internalrequest(HTTP.Request("GET", "/anonymous"))
    @test r.status == 200
    @test text(r) == "no args"

    r = internalrequest(HTTP.Request("GET", "/fake-endpoint"))
    @test r.status == 404

    r = internalrequest(HTTP.Request("GET", "/test"))
    @test r.status == 200
    @test text(r) == "hello world!"

    r = internalrequest(HTTP.Request("GET", "/multiply/5/8"))
    @test r.status == 200
    @test text(r) == "40.0"

    r = internalrequest(HTTP.Request("GET", "/person"))
    @test r.status == 200
    @test json(r, Person) == Person("joe", 20)

    r = internalrequest(HTTP.Request("GET", "/html"))
    @test r.status == 200
    @test Dict(r.headers)["Content-Type"] == "text/html; charset=utf-8"


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

    r = internalrequest(HTTP.Request("GET", "/static/content/test.txt"))
    body = text(r)
    @test r.status == 200
    @test Dict(r.headers)["Content-Type"] == "text/plain; charset=utf-8"
    @test body == file("content/test.txt")
    @test body == "this is a sample text file"

    r = internalrequest(HTTP.Request("GET", "/static/content/sample.html"))
    @test r.status == 200
    @test Dict(r.headers)["Content-Type"] == "text/html; charset=utf-8"
    @test text(r) == file("content/sample.html")


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


    r = internalrequest(HTTP.Request("GET", "/dynamic/content/sample.html"))
    @test r.status == 200
    @test text(r) == file("content/sample.html")

    r = internalrequest(HTTP.Request("GET", "/static/content/sample.html"))
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

    r = internalrequest(HTTP.Request("GET", "/unsupported-struct"))
    @test r.status == 500

    @async serve()
    sleep(1)

    r = internalrequest(HTTP.Request("GET", "/get"))
    @test r.status == 200
    
    terminate()

    @async serve((req, router, defaultHandler) -> defaultHandler(req))
    sleep(1)

    r = internalrequest(HTTP.Request("GET", "/get"))
    @test r.status == 200

    # redundant terminate() calls should have no affect
    terminate()
    terminate()
    terminate()


    # only run these tests if we have more than one thread to work with
    if Threads.nthreads() > 1

        @async serveparallel()
        sleep(1)
    
        r = HTTP.get("$localhost/get")
        @test r.status == 200

        r = HTTP.post("$localhost/post", body="some demo content")
        @test text(r) == "some demo content"

        try
            r = HTTP.get("$localhost/customerror")
        catch e 
            @test e isa MethodError || e isa HTTP.ExceptionRequest.StatusError
        end
        
        HTTP.get("$localhost/killserver")
   
        @async serveparallel((req, router, defaultHandler) -> defaultHandler(req))
        sleep(1)

        r = HTTP.get("$localhost/get")
        @test r.status == 200

        HTTP.get("$localhost/killserver")

        try 
            @async serveparallel(queuesize=0)
            r = HTTP.get("$localhost/get")
        catch e
            @test e isa HTTP.ExceptionRequest.StatusError
        finally
            terminate()
        end

    else 

        # service should not have started and get requests should throw some error
        @async serveparallel()
        sleep(1)
        try 
            r = HTTP.get("$localhost/get"; readtimeout=1)
        catch e
            @test true
        end
        terminate()

    end

end 
