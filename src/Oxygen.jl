module Oxygen

using MacroTools: splitdef, combinedef

const WAS_LOADED_AFTER_REVISE :: Ref{Bool} = Ref(false)

function __init__()
    if isdefined(Main, :Revise)
        WAS_LOADED_AFTER_REVISE[] = true
    end
end

include("core.jl"); using .Core
include("instances.jl"); using .Instances

import HTTP: Request, Response, Stream, WebSocket, queryparams
using .Core: ServerContext, History, Server, Nullable
using .Core: GET, POST, PUT, DELETE, PATCH
using .Core.ContextExt: register_ext, @register_ext

const CONTEXT :: Ref{ServerContext} = Ref(ServerContext())

import Base: get 
include("exts.jl")
include("methods.jl")
include("deprecated.jl")

module OxygenExt
    __precompile__(false)
    import ..CONTEXT
end

const EXT_METHOD_MODULES::Vector{Module} = Module[OxygenExt]
const EXT_METHOD_STUBS::Vector{Expr} = Expr[]

macro oxidise()
    (quote
        import Oxygen
        import Oxygen: PACKAGE_DIR, ServerContext, Nullable
        import Oxygen: GET, POST, PUT, DELETE, PATCH, STREAM, WEBSOCKET

        const CONTEXT :: Ref{ServerContext}  = Ref(ServerContext(; mod=$(__module__)))
        include(joinpath(PACKAGE_DIR, "methods.jl"))
        module OxygenExt
            __precompile__(false)
            using ..CONTEXT
            for method_stub in Oxygen.EXT_METHOD_STUBS
                eval(method_stub)
            end
        end
        push!(Oxygen.EXT_METHOD_MODULES, OxygenExt)
        using .OygenExt: OxygenExt
        
        nothing; # to hide last definition
    end).args |> esc
end

function add_stub!(stub::Expr)
    push!(EXT_METHOD_STUBS, stub)
    for mod in EXT_METHOD_MODULES
        mod.eval(stub)
    end
end

function generate_stub(name, mod)
    #full_mod = fullname(mod)
    #full_mod_expr = Expr(:., )
    #full_mod_expr = Expr(:., full_mod..., name)
    quote 
        #using $((full_mod..., name)...)
        function $(name)(args...; kwargs...)
            #$(full_mod...).$(name)(CONTEXT[], args...; kwargs...)
            $mod.$(name)(CONTEXT[], args...; kwargs...)
        end
    end
end

macro contextmethod(fdecl)
    fdecl_bits = splitdef(fdecl)
    add_stub!(generate_stub(fdecl_bits[:name], __module__))
    insert!(fdecl_bits[:args], 1, :(context::$(ServerContext)))
    return :($(esc(combinedef(fdecl_bits))))
end

export  @oxidise, @get, @post, @put, @patch, @delete, @route, 
        @staticfiles, @dynamicfiles, @cron, @repeat, @stream, @websocket,
        get, post, put, patch, delete, route, stream, websocket,
        serve, serveparallel, terminate, internalrequest, 
        resetstate, instance, staticfiles, dynamicfiles,
        # Util
        redirect, formdata, format_sse_message,
        html, text, json, file, xml, js, css, binary,
        # Extractors
        Path, Query, Header, Json, JsonFragment, Form, Body, extract, validate,
        # Docs
        configdocs, mergeschema, setschema, getschema, router,
        enabledocs, disabledocs, isdocsenabled, 
        # Tasks & Cron
        starttasks, stoptasks, cleartasks,
        startcronjobs, stopcronjobs, clearcronjobs, 
        # Common HTTP Types
        Request, Response, Stream, WebSocket, queryparams,
        # Context Types and methods
        Context, context,
        # Ext
        @register_ext, register_ext, OxygenExt
end
