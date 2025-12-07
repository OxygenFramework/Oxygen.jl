module Oxygen

const WAS_LOADED_AFTER_REVISE :: Ref{Bool} = Ref(false)

function __init__()
    if isdefined(Main, :Revise)
        WAS_LOADED_AFTER_REVISE[] = true
    end
end

include("core.jl"); using .Core
include("instances.jl"); using .Instances

import HTTP: Request, Response, Stream, WebSocket, queryparams
using .Core: ServerContext, History, Server, Nullable, HOFRouter
using .Core: GET, POST, PUT, DELETE, PATCH

const CONTEXT :: Ref{ServerContext} = Ref(ServerContext())

import Base: get 
include("exts.jl")
include("methods.jl")
include("deprecated.jl")

macro oxidize()
    quote
        import Oxygen
        import Oxygen: PACKAGE_DIR, ServerContext, Nullable, HOFRouter
        import Oxygen: GET, POST, PUT, DELETE, PATCH, STREAM, WEBSOCKET

        const CONTEXT :: Ref{ServerContext}  = Ref(ServerContext(; mod=$(__module__)))
        include(joinpath(PACKAGE_DIR, "methods.jl"))
        
        nothing; # to hide last definition
    end |> esc
end

export  @oxidize, @oxidise, @get, @post, @put, @patch, @delete, @route, 
        @staticfiles, @dynamicfiles, @cron, @repeat, @stream, @websocket,
        get, post, put, patch, delete, route, stream, websocket,
        serve, serveparallel, terminate, internalrequest, 
        resetstate, instance, staticfiles, dynamicfiles,
        # Util
        redirect, formdata, format_sse_message,
        html, text, json, file, xml, js, css, binary,
        # Extractors
        Path, Query, Header, Json, JsonFragment, Form, Body, extract, validate,
        # Middleware
        BearerAuth, bearer_auth, Cors, cors, RateLimiter, rate_limiter,
        # Docs
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, 
        # Tasks & Cron
        starttasks, stoptasks, cleartasks,
        startcronjobs, stopcronjobs, clearcronjobs, 
        # Common HTTP Types
        Request, Response, Stream, WebSocket, queryparams,
        # Context Types and methods
        Context, context
end
