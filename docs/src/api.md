# Api

Documentation for Oxygen.jl

## Starting the webserver
```@docs 
serve
serveparallel
```

## Routing 

```@docs
@get(path, func)
@post(path, func)
@put(path, func)
@patch(path, func)
@delete(path, func)
@route(methods, path, func)
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
