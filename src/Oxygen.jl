module Oxygen

include("core.jl"); using .Core
# Load any optional extensions
include("extensions/load.jl");

import HTTP: Request, Response
using .Core: Context, History, Server

const CONTEXT = Ref{Context}(Context())

import Base 
include("methods.jl")
include("deprecated.jl")


macro oxidise()
    quote
        import Base
        import Oxygen: Context
        
        const CONTEXT = Ref{Context}(Context())
        include(joinpath(dirname(Base.find_package("Oxygen")), "methods.jl"))
        
        nothing; # to hide last definition
    end |> esc
end


export  @oxidise, @get, @post, @put, @patch, @delete, @route, @cron, 
        @staticfiles, @dynamicfiles, Request, Response, 
        get, post, put, patch, delete, route,
        serve, serveparallel, terminate, internalrequest, 
        staticfiles, dynamicfiles,
        redirect, queryparams, formdata,
        html, text, json, file, xml, js, json, css, binary,
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, 
        starttasks, stoptasks, cleartasks,
        startcronjobs, stopcronjobs, clearcronjobs, 
        resetstate
end
