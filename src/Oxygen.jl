module Oxygen

include("core.jl"); using .Core
include("instances.jl"); using .Instances
# Load any optional extensions
include("extensions/load.jl");

import HTTP: Request, Response
using .Core: Context, History, Server

const CONTEXT = Ref{Context}(Context())

import Base: get 
include("methods.jl")
include("deprecated.jl")

macro oxidise()
    quote
        import Oxygen
        
        const CONTEXT = Ref{Oxygen.Context}(Oxygen.Context())
        include(joinpath(dirname(Base.find_package("Oxygen")), "methods.jl"))
        
        nothing; # to hide last definition
    end |> esc
end

export  @oxidise, @get, @post, @put, @patch, @delete, @route, @cron, 
        @staticfiles, @dynamicfiles,
        get, post, put, patch, delete, route,
        serve, serveparallel, terminate, internalrequest, 
        resetstate, instance, staticfiles, dynamicfiles,
        # Util
        redirect, queryparams, formdata,
        html, text, json, file, xml, js, json, css, binary,
        # Docs
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, 
        # Tasks & Cron
        starttasks, stoptasks, cleartasks,
        startcronjobs, stopcronjobs, clearcronjobs, 
        # Common HTTP Types
        Request, Response
end
