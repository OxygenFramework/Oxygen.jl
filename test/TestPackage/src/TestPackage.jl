module TestPackage

using Base: @kwdef

push!(LOAD_PATH, "../../")
using Oxygen; @oxidize

export start, stop

@kwdef struct Add
    a::Int
    b::Int = 3
end

get("/") do
    text("hello world")
end

@get "/add" function(req::Request, a::Int, b::Int=3)
    a + b
end

@get "/add/extractor" function(req::Request, qparams::Query{Add})
    add = qparams.payload
    add.a + add.b
end

start(;kwargs...) = serve(;kwargs...)
stop() = terminate()

end
