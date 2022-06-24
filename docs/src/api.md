# Api

Documentation for Oxygen.jl

## Starting the webserver
```@docs 
serve(host="127.0.0.1", port=8080; suppresserrors::Bool=false, kwargs...)
serve(handler::Function, host="127.0.0.1", port=8080; kwargs...)
serveparallel(host="127.0.0.1", port=8080, queuesize=1024; kwargs...)
serveparallel(handler::Function, host="127.0.0.1", port=8080, queuesize=1024; kwargs...)
```

## Routing 

```@docs
@get(path, func)
@post(path, func)
@put(path, func)
@patch(path, func)
@delete(path, func)
@route(methods, path, func)
@register
```

## Mounting Files
```@docs
@staticfiles
@dynamicfiles
file
```

## Swagger Docs
```@docs
configdocs 
enabledocs
disabledocs
isdocsenabled
mergeschema
setschema
getschema
```

## Helper functions 
```@docs 
queryparams
html
text
json
binary
```

## Extra's
```@docs 
internalrequest
terminate()
```
