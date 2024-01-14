module Oxygen
using HTTP
using JSON3
using Sockets
using Reexport

include("core.jl"); @reexport using .Core

# Load any optional extensions
include("extensions/load.jl");

export @get, @post, @put, @patch, @delete, @route, @cron, 
        @staticfiles, @dynamicfiles, staticfiles, dynamicfiles,
        get, post, put, patch, delete, route,
        serve, serveparallel, terminate, internalrequest, 
        redirect, queryparams, binary, text, json, html, file, 
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, starttasks, stoptasks,
        resetstate, startcronjobs, stopcronjobs, clearcronjobs
end