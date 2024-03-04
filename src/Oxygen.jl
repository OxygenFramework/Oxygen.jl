module Oxygen

include("core.jl"); using .Core
include("instances.jl"); using .Instances
include("extensions/load.jl");

import HTTP: Request, Response
using .Core: Context, History, Server, Nullable

const CONTEXT = Ref{Context}(Context())

import Base: get 
include("methods.jl")
include("deprecated.jl")

macro oxidise()
    quote
        import Oxygen

        const Context = Oxygen.Context
        const Nullable = Oxygen.Core.Types.Nullable
        
        const CONTEXT = Ref{Context}(Context())
        include(joinpath(dirname(Base.find_package("Oxygen")), "methods.jl"))
        
        nothing; # to hide last definition
    end |> esc
end

export  @oxidise, @get, @post, @put, @patch, @delete, @route, 
        @staticfiles, @dynamicfiles, @cron, @repeat,
        get, post, put, patch, delete, route,
        serve, serveparallel, terminate, internalrequest, 
        resetstate, instance, staticfiles, dynamicfiles,
        # Util
        redirect, queryparams, formdata,
        html, text, json, file, xml, js, css, binary,
        # Docs
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, 
        # Tasks & Cron
        starttasks, stoptasks, cleartasks,
        startcronjobs, stopcronjobs, clearcronjobs, 
        # Common HTTP Types
        Request, Response
end
