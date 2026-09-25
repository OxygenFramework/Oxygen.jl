module CoreUtils

using HTTP
using JSON
using ..CoreTypes: Nullable, Param, LazyRequest, LifecycleMiddleware
using ...Util

export startup, shutdown, isrequired, headers, pathparams, queryvars,
    jsonbody, formbody, textbody

# A parameter is required only when it has no default at all. A default of
# `missing`/`nothing` is still a default, so the handler's own default applies.
isrequired(p::Param) = !p.hasdefault

function startup(lf::LifecycleMiddleware)
    if !isnothing(lf.on_startup)
        try 
            lf.on_startup()
        catch error
            @error "Error in LifecycleMiddleware.on_startup: " exception=(error, catch_backtrace())
        end
    end
end

function shutdown(lf::LifecycleMiddleware)
    if !isnothing(lf.on_shutdown)
        try
            lf.on_shutdown()
        catch error
            @error "Error in LifecycleMiddleware.on_shutdown: " exception=(error, catch_backtrace())
        end
    end
end

function headers(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.headers[])
        req.headers[] = Dict(req.request.headers)
    end
    return req.headers[] 
end

function pathparams(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.pathparams[])
        req.pathparams[] = HTTP.getparams(req.request)
    end
    return req.pathparams[] 
end

function queryvars(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.queryparams[])
        req.queryparams[] = HTTP.queryparams(HTTP.URI(req.request.target).query)
    end
    return req.queryparams[]
end

function jsonbody(req::LazyRequest) :: Nullable{JSON.Object}
    if isnothing(req.jsonbody[])
        req.jsonbody[] = json(req.request)
    end
    return req.jsonbody[] 
end

function formbody(req::LazyRequest) :: Nullable{Dict{String,String}}
    if isnothing(req.formbody[])
        req.formbody[] = formdata(req.request)
    end
    return req.formbody[] 
end

function textbody(req::LazyRequest) :: Nullable{String}
    if isnothing(req.textbody[])
        req.textbody[] = text(req.request)
    end
    return req.textbody[] 
end

end
