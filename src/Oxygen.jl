module Oxygen
using HTTP
using JSON3
using Sockets

include("util.jl" );        using .Util
include("bodyparsers.jl");  using .BodyParsers
include("core.jl");         using .Core

export @get, @post, @put, @patch, @delete, @route, @cron, 
        @staticfiles, @dynamicfiles, staticfiles, dynamicfiles,
        get, post, put, patch, delete, route,
        serve, serveparallel, servedebug, terminate, internalrequest, 
        redirect, queryparams, binary, text, json, html, file, 
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, starttasks, stoptasks,
        clear_routes, resetstate, startcronjobs, stopcronjobs
end
