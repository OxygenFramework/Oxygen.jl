module Oxygen

include("core.jl"); using .Core
# Load any optional extensions
#include("extensions/load.jl");

import HTTP
#const ROUTER = Ref{HTTP.Handlers.Router}(HTTP.Router())
const SERVER = Ref{Union{HTTP.Server, Nothing}}(nothing) 

using DataStructures: CircularDeque
using .Core.Metrics: HTTPTransaction
const HISTORY = Ref{CircularDeque{HTTPTransaction}}(CircularDeque{HTTPTransaction}(1_000_000))

using .Core.StreamUtil: Handler
const HANDLER = Ref{Handler}(Handler())

#using .Core.AutoDoc: TaggedRoute
#MOUNTED_FOLDERS = Set{String}()
#TAGGED_ROUTES = Dict{String, TaggedRoute}()
#const CUSTOM_MIDDLEWARE = Ref{Dict{String, Tuple}}(Dict())

using .Core: Context
const CONTEXT = Ref{Context}(Context())


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
