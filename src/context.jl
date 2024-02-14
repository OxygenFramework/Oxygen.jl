module AppContext
import Base: @kwdef
using HTTP: Router
using ..Types: TaggedRoute

export Context

function defaultSchema()
    Dict(
        "openapi" => "3.0.0",
        "info" => Dict(
            "title" => "API Overview",
            "version" => "1.0.0"
        ),
        "paths" => Dict()
    )
end

"""
Define our application Context object with default values
"""
@kwdef struct Context
    router::Router                              = Router()
    mountedfolders::Set{String}                 = Set{String}()
    taggedroutes::Dict{String, TaggedRoute}     = Dict{String, TaggedRoute}()
    custommiddleware::Dict{String, Tuple}       = Dict{String, Tuple}()
    repeattasks::Vector                         = []
    schema::Dict                                = defaultSchema()
    job_definitions::Set                        = Set()
end


@eval begin
    """
        Context(ctx::Context; kwargs...)

    Create a new `Context` object by copying an existing one and optionally overriding some of its fields with keyword arguments.
    """
    function Context(ctx::Context; $([Expr(:kw ,k, :(ctx.$k)) for k in fieldnames(Context)]...))
        return Context($(fieldnames(Context)...))
    end
end

end


# # Created within a `serve` at runtime. Keyword arguments may be used to initialize some of the objects outside.
# struct Runtime
#     run::Ref{Bool}
#     jobs::Set
#     timers::Vector{Timer}
#     history::CircularDeque{HTTPTransaction}
#     streamhandler::Union{Nothing, StreamUtil.Handler}
# end

# # Returned from `serve` when async is enabled.
# struct Service
#     context::Context
#     runtime::Runtime
#     server::HTTP.Server
# end
