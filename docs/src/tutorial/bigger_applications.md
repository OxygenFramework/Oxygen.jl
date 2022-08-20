# Bigger Applications - Multiple Files

If you are building an application or a web API, it's rarely the case that you can put everything on a single file.

As your application grows you'll need to spread your application's logic across multiple files. Oxygen provides some tools to help you do this while staying organized.

Let's say you have an application that looks something like this:

```
app
├── src
│   ├── main.jl
│   └── MathOperations.jl
│
├── Project.toml
└── Manifest.toml
```

## How to use the `router()` function

Let's say you have a file dedicated to handling mathematical operations in the submodule at `/src/MathOperations.jl.`

You might want the first part of each path to have the same value and just switch out the subpath to keep things organized in your api. You can use the `router` function to do just that. 

The `router()` function is an HOF (higher order function) that allows you to reuse the same properties across multiple endpoints.

Because the generated router is just a function, they can be exported and shared across multiple files & modules.

```julia
using Oxygen

math = router("/math", tags=["math"])

@get math("/multiply/{a}/{b}", tags=["multiplication"]) function(req, a::Float64, b::Float64)
    return a * b
end

@get math("/divide/{a}/{b}") function(req, a::Float64, b::Float64)
    return a / b
end

serve()
```
## Tagging your routes

By using the hello router in both endpoints, it passes along all the properties as default values. For example If we look at the routes registered in the application they will look like:
```
/math/multiply/{a}/{b}
/math/divide/{a}/{b}
```

Both endpoints in this case will be tagged to the `math` tag and the `/multiply` endpoint will have an additional tag appended just to this endpoint called `multiplication`. These tags are used by Oxygen when auto-generating the documentation to organize it by separating the endpoints into sections based off their tags. 


## Middleware & `router()`

The `router()` function has a `middleware` parameter which takes a vector of middleware functions
which are used to intercept all incoming requests & outgoing responses.

All middleware is additive and any middleware defined in these layers will be combined and executed.

You can assign middleware at three levels:
- `application` 
- `router` 
- `route` 

Middleware will always get executed in the following order:

```
application -> router -> route
```

the `application` layer can only be set from the `serve()` and `serveparallel()` functions. While the other two layers can be set using the `router()` function.

```julia
# Set middleware at the application level
serve(middleware=[])

# Set middleware at the Router level
myrouter = router("/router", middleware=[])

# Set middleware at the Route level
@get myrouter("/example", middleware=[]) function()
    return "example"
end
```


### Router Level Middleware

At the router level, any middleware defined here will be reused across 
all other routes that use this router(). In the example below, both `/greet/hello` 
and `/greet/bonjour` routes will send requests through the same middleware functions before either endpoint is called

```julia
function middleware1(handle)
    function(req)
        println("this is the 1st middleware function")
        handle(req)
    end
end

# middleware1 is defined at the router level
greet = router("/greet", middleware=[middleware1])

@get greet("/hello") function()
    println("hello")
end

@get greet("/bonjour") function()
    println("bonjour")
end
```

### Route Specific Middleware

At the route level, you can customize what middleware functions should be
applied on a route by route basis. In the example below, the `/greet/hello` route
gets both `middleware1` & `middleware2` functions applied to it, while the `/greet/bonjour` 
route only has `middleware1` function which it inherited from the `greet` router.

```julia
function middleware1(handle)
    function(req)
        println("this is the 1st middleware function")
        handle(req)
    end
end

function middleware2(handle)
    function(req)
        println("this is the 2nd middleware function")
        handle(req)
    end
end

# middleware1 is added at the router level
greet = router("/greet", middleware=[middleware1])

# middleware2 is added at the route level
@get greet("/hello", middleware=[middleware2]) function()
    println("hello")
end

@get greet("/bonjour") function()
    println("bonjour")
end

serve()
```

### Skipping Middleware layers

Well, what if we don't want previous layers of middleware to run? 
By setting `middleware=[]`, it clears all middleware functions at that layer and skips all layers that come before it. These changes are localized and only affect the components where these values are set.

For example, setting `middleware=[]` at the:
- application layer -> clears the application layer
- router layer -> no application middleware is applied to this router
- route layer -> no router middleware is applied to this route

You can set the router's `middleware` parameter to an empty vector to bypass any application level middleware.
In the example below, all requests to endpoints registered to the `greet` router() will skip any application level 
middleware and get executed directly.

```julia
function middleware1(handle)
    function(req)
        println("this is the 1st middleware function")
        handle(req)
    end
end

greet = router("/greet", middleware=[])

@get greet("/hello") function()
    println("hello")
end

@get greet("/bonjour") function()
    println("bonjour")
end

serve(middleware=[middleware1])
```

## Repeat Actions

The `router()` function has an `interval` parameter which is used to call
a request handler on a set interval (in seconds). 

**It's important to note that request handlers that use this property can't define additional function parameters outside of the default `HTTP.Request` parameter.**

In the example below, the `/repeat/hello` endpoint is called every 0.5 seconds and `"hello"` is printed to the console each time.

```julia
using Oxygen

repeat = router("/repeat", interval=0.5, tags=["repeat"])

@get repeat("/hello") function()
    println("hello")
end

# you can override properties by setting route specific values 
@get repeat("/bonjour", interval=1.5) function()
    println("bonjour")
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