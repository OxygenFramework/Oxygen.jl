module Oxygen
using HTTP
using JSON3
using Sockets

include("util.jl" );        using .Util
include("fileutil.jl");     using .FileUtil
include("bodyparsers.jl");  using .BodyParsers
include("serverutil.jl");   using .ServerUtil

export @get, @post, @put, @patch, @delete, @route, @staticfiles, @dynamicfiles,
        serve, serveparallel, terminate, internalrequest, 
        redirect, queryparams, binary, text, json, html, file, 
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled
end