module Oxygen

include("core.jl"); using .Core
# Load any optional extensions
include("extensions/load.jl");

import HTTP: Request, Response
using .Core: Context, History, Server

const CONTEXT = Ref{Context}(Context())
const SERVICE = Ref{Union{Service, Nothing}}(nothing)


import Base: get 
include("methods.jl")
include("deprecated.jl")


macro oxidise()
    quote
        import Oxygen
        
        const CONTEXT = Ref{Oxygen.Context}(Oxygen.Context())
        const SERVICE = Ref{Union{Service, Nothing}}(nothing)

        include(joinpath(dirname(Base.find_package("Oxygen")), "methods.jl"))
        
        nothing; # to hide last definition
    end |> esc
end


export @get, @post, @put, @patch, @delete, @route, @cron, 
        @staticfiles, @dynamicfiles, staticfiles, dynamicfiles,
        get, post, put, patch, delete, route,
        serve, serveparallel, terminate, internalrequest, 
        redirect, queryparams, formdata,
        html, text, json, file, xml, js, json, css, binary,
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, starttasks, stoptasks,
        resetstate, startcronjobs, stopcronjobs, clearcronjobs, 
        @oxidise, Request, Response # frequently needed when Oxygen is used
end
