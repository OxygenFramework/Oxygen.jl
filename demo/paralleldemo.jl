module ParallelDemo 

    include("../src/Oxygen.jl")
    using .Oxygen
    using HTTP
    using JSON3
    using StructTypes
    using SwaggerMarkdown
    using SwagUI
    using Base.Threads

    StructTypes.StructType(::Type{Atomic{Int64}}) = StructTypes.Struct()

    x = Atomic{Int64}(0);
    
    @get "/show" function()
        return x
    end

    @get "/increment" function()
        atomic_add!(x, 1)
        return x
    end

    # start the web server in parallel mode
    serveparallel()
end