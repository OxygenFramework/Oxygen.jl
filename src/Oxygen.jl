module Oxygen

include("core.jl"); using .Core
# Load any optional extensions
include("extensions/load.jl");

import HTTP: Request
using .Core: Context, History, Server

const CONTEXT = Ref{Context}(Context())
const SERVER = Ref{Union{Server, Nothing}}(nothing) 
const HISTORY = Ref{History}(History(1_000_000))

import Base: get 
include("methods.jl")
include("deprecated.jl")


macro oxidise()
    quote
        import Oxygen
        
        const CONTEXT = Ref{Oxygen.Context}(Oxygen.Context())
        const SERVER = Ref{Union{Oxygen.Server, Nothing}}(nothing)
        const HISTORY = Ref{Oxygen.History}(Oxygen.History(1_000_000))

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
        @oxidise, Request # frequently needed when Oxygen is used
end
