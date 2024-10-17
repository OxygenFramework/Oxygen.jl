module Oxygen

const WAS_LOADED_AFTER_REVISE = Ref(false)

function __init__()
    if isdefined(Main, :Revise)
        WAS_LOADED_AFTER_REVISE[] = true
    end
    do_requires()
end

include("core.jl"); using .Core
include("instances.jl"); using .Instances
include("extensions/load.jl");

import HTTP: Request, Response, Stream, WebSocket, queryparams
using .Core: Context, History, Server, Nullable
using .Core: GET, POST, PUT, DELETE, PATCH

const CONTEXT = Ref{Context}(Context())

import Base: get 
include("methods.jl")
include("deprecated.jl")

macro oxidise()
    quote
        import Oxygen
        import Oxygen: PACKAGE_DIR, Context, Nullable
        import Oxygen: GET, POST, PUT, DELETE, PATCH, STREAM, WEBSOCKET

        const CONTEXT = Ref{Context}(Context(; mod=$(__module__)))
        include(joinpath(PACKAGE_DIR, "methods.jl"))
        
        nothing; # to hide last definition
    end |> esc
end

export  @oxidise, @get, @post, @put, @patch, @delete, @route, 
        @staticfiles, @dynamicfiles, @cron, @repeat, @stream, @websocket,
        get, post, put, patch, delete, route, stream, websocket,
        serve, serveparallel, terminate, internalrequest, 
        resetstate, instance, staticfiles, dynamicfiles,
        # Util
        redirect, formdata, format_sse_message,
        html, text, json, file, xml, js, css, binary,
        # Extractors
        Path, Query, Header, Json, JsonFragment, Form, Body, extract, validate,
        # Docs
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, 
        # Tasks & Cron
        starttasks, stoptasks, cleartasks,
        startcronjobs, stopcronjobs, clearcronjobs, 
        # Common HTTP Types
        Request, Response, Stream, WebSocket, queryparams
end
