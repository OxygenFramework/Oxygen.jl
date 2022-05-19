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
        return Person("joe", 20)
    end 
    
    r = internalrequest(HTTP.Request("GET", "/test"))
    @test r.status == 200
    @test text(r) == "hello world!"

    r = internalrequest(HTTP.Request("GET", "/multiply/5/8"))
    @test r.status == 200
    @test text(r) == "40.0"

    r = internalrequest(HTTP.Request("GET", "/multiply/a/8"), true)
    @test r.status == 500

    r = internalrequest(HTTP.Request("GET", "/json"))
    @test r.status == 200
    @test json(r, Person)== Person("joe", 20)
end 