module AppContext
import Base: @kwdef, wait, close, isopen
using HTTP
using HTTP: Server, Router
using ..Types

export Context, CronContext, TasksContext, Documenation, Service, history, wait, close, isopen


function defaultSchema() :: Dict
    Dict(
        "openapi" => "3.0.0",
        "info" => Dict(
            "title" => "API Overview",
            "version" => "1.0.0"
        ),
        "paths" => Dict()
    )
end

@kwdef struct CronContext
    run::Ref{Bool}          = Ref{Bool}(false)  # Flag used to stop all running tasks
    jobs::Set               = Set()   # Set of all running tasks
    job_definitions::Set    = Set()   # Cron job definitions registered through the router() (path, httpmethod, cron_expression)
    cronjobs::Set           = Set()   # Set of cron expressions and functions (expression, name, function)
end

@kwdef struct TasksContext
    timers::Vector{Timer}   = [] # Vector of all running tasks
    task_definitions::Set   = Set() # Set of all registered task definitions ()
    repeattasks::Set        = Set() # Vector of repeat task definitions (path, httpmethod, interval)
end

@kwdef struct Documenation
    router::Ref{Nullable{Router}}           = Ref{Nullable{Router}}(nothing)    # used for docs & metrics internal endpoints
    docspath::Ref{String}                   = Ref{String}("/docs")
    schemapath::Ref{String}                 = Ref{String}("/schema")
    schema::Dict                            = defaultSchema()
    taggedroutes::Dict{String, TaggedRoute} = Dict{String, TaggedRoute}()       # used to group routes by tag
end

@kwdef struct Service
    server::Ref{Nullable{Server}}           = Ref{Nullable{Server}}(nothing)
    router::Router                          = Router()
    custommiddleware::Dict{String, Tuple}   = Dict{String, Tuple}()
    history::History                        = History(1_000_000)
    parallel_handler::Ref{Nullable{Handler}} = Ref{Nullable{Handler}}(nothing)
end

@kwdef struct Context
    service::Service        = Service()    
    docs::Documenation      = Documenation()
    cron::CronContext       = CronContext()
    tasks::TasksContext     = TasksContext()
end

Base.isopen(service::Service)   = !isnothing(service.server[]) && isopen(service.server[])
Base.close(service::Service)    = !isnothing(service.server[]) && close(service.server[])
Base.wait(service::Service)     = !isnothing(service.server[]) && wait(service.server[])


# @eval begin
#     """
#         Context(ctx::Context; kwargs...)

#     Create a new `Context` object by copying an existing one and optionally overriding some of its fields with keyword arguments.
#     """
#     function Context(ctx::Context; $([Expr(:kw ,k, :(ctx.$k)) for k in fieldnames(Context)]...))
#         return Context($(fieldnames(Context)...))
#     end
# end

end
