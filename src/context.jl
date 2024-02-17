module AppContext
import Base: @kwdef, wait, close
using HTTP
using HTTP: Router
using ..Types

export Context, CronRuntime, TasksRuntime, Documenation, Service, history, wait, close

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

@kwdef struct CronRuntime
    run::Ref{Bool}          = Ref{Bool}(false)  # Flag used to stop all running tasks
    jobs::Set               = Set()   # Set of all running tasks
    cronjobs::Set           = Set()   # Cron job definitions registered through the router() (path, httpmethod, cron_expression)
    job_definitions::Set    = Set()   # Set of cron expressions and functions
end

@kwdef struct TasksRuntime
    timers::Vector{Timer}   = [] # Vector of running tasks
    repeattasks::Set        = Set() # Vector of repeat task definitions (path, httpmethod, interval)
end

@kwdef struct Documenation
    docspath::Ref{String}                   = "/docs"
    schemapath::Ref{String}                 = "/schema"
    schema::Dict                            = defaultSchema()
    mountedfolders::Set{String}             = Set{String}()                 # Set of all mounted folders for file hosting
    taggedroutes::Dict{String, TaggedRoute} = Dict{String, TaggedRoute}()
end

@kwdef struct Service
    server::Ref{Union{HTTP.Server,Nothing}} = Ref{Union{HTTP.Server,Nothing}}(nothing)
    router::Router                          = Router()
    custommiddleware::Dict{String, Tuple}   = Dict{String, Tuple}()
    history::History                        = History(1_000_000)
end

@kwdef struct Context
    service::Service        = Service()    
    docs::Documenation      = Documenation()
    cron::CronRuntime       = CronRuntime()
    tasks::TasksRuntime     = TasksRuntime()
end


Base.close(context::Context) = close(context.service.server[])
Base.wait(context::Context) = wait(context.service.server[])

Base.close(service::Service) = close(service.server[])
Base.wait(service::Service) = wait(service.server[])

history(context::Context) = context.service.history


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
