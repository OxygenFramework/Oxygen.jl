module Oxygen

include("core.jl"); using .Core
# Load any optional extensions
#include("extensions/load.jl");

import HTTP
global const ROUTER = Ref{HTTP.Handlers.Router}(HTTP.Router())
global const SERVER = Ref{Union{HTTP.Server, Nothing}}(nothing) 


include("methods.jl")

export @get, @post, @put, @patch, @delete, @route, @cron, 
        @staticfiles, @dynamicfiles, staticfiles, dynamicfiles,
        get, post, put, patch, delete, route,
        serve, serveparallel, terminate, internalrequest, 
        redirect, queryparams, formdata,
        html, text, json, file, xml, js, json, css, binary,
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, starttasks, stoptasks,
        resetstate, startcronjobs, stopcronjobs, clearcronjobs
end
