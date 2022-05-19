module RunTests 
    using Test
    using HTTP
    using JSON3
    using StructTypes

    include("../src/Oxygen.jl")
    using .Oxygen

    struct Person
        name::String
        age::Int
    end

    StructTypes.StructType(::Type{Person}) = StructTypes.Struct()

    @get "/anonymous" function()
        return "no args"
    end

    @get "/test" function(req)
        return "hello world!"
    end

    @get "/multiply/{a}/{b}" function(req, a::Float64, b::Float64)
        return a * b 
    end

    @get "/json" function(req)
        return Person("nate", 26)
    end

    suppresserrors()
    
    r = internalrequest(HTTP.Request("GET", "/test"))
    @test r.status == 200
    @test String(r.body) == "hello world!"

    r = internalrequest(HTTP.Request("GET", "/multiply/5/8"))
    @test r.status == 200
    @test String(r.body) == "40.0"

    r = internalrequest(HTTP.Request("GET", "/multiply/a/8"))
    @test r.status == 500

    r = internalrequest(HTTP.Request("GET", "/json"))
    println(JSON3.read(String(r.body)))
end 