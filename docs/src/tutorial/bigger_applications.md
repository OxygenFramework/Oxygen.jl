# Bigger Applications - Multiple Files

If you are building an application or a web API, it's rarely the case that you can put everything on a single file.

As your application grows you'll need to spread your application's logic across multiple files. Oxygen provides some tools to help you do this while staying organized.


Let's say you have an application that looks something like this:

```
app
├── src
│   ├── main.jl
│   └── routers
│       ├── users.jl
│       └── items.jl
├── Project.toml
└── Manifest.toml
```

### `router()`

Let's say the file dedicated to handling just users is the submodule at /src/routers/users.jl.

You want to have the path operations related to your users separated from the rest of the code, to keep it organized.

You can create the path operations for that module using the `router` function. 

The `router()` function is HOF (higher order function) that allows you to reuse the same properties on all other nested routes. 

```julia
using Oxygen

hello = router("/greet/v1/greeting", tags=["greet"])

@get hello("/hi", tags=["welcome"]) function(req)
    return "hi"
end

@get hello("/hello") function(req)
    return "hello"
end

serve()
```

By using the hello router in both endpoints, it passes along all the properties as default values. For example If we look at the routes registered in the application they will look like:

`/greet/v1/greeting/hi`
`/greet/v1/greeting/hello`

Both endpoints in this case will be tagged to the `greet` tag and the `/hi` endpoint will have an additional tag appended just to this endpoint called `welcome`. These tags are used by Oxygen when auto-generating the documentation to organize it by separating the endpoints into sections based off their tags. 


The `router()` function also has an `interval` parameter which is used to call
an request handler on a set interval (in seconds). **It's important to note that request handlers that use this property can't define additional function parameters outside of the default `HTTP.Request` parameter.**

In the example below, the `/repeat/hello` endpoint is called every 0.5 seconds and `"hello"` is printed to the console on every call

```julia
using HTTP
using Oxygen

repeat = router("/repeat", interval=0.5, tags=["repeat"])

@get repeat("/hello") function(req::HTTP.Request)
    println("hello")
    return "hello"
end

serve()
```

If you want to call an endpoint with parameters on a set interval, you're better off creating an endpoint to perform the action you want and a second endpoint to call the first on a set interval. 

```julia
using HTTP
using Oxygen

repeat = router("/repeat", interval=1.5, tags=["repeat"])

@get "/multiply/{a}/{b}" function(req, a::Float64, b::Float64)
    return a * b
end

@get repeat("/multiply") function()
    response = internalrequest(HTTP.Request("GET", "/multiply/3/5"))
    println(response)
    return response
end

serve()
```

The example above will print the response from the `/multiply` endpoint in the console below every 1.5 seconds and should look like this:

```
"""
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

15.0"""
```