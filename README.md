# Oxygen.jl
</br>
<p align="center"><img src="oxygen.png" width="20%"></p>
<p align="center">
  <strong>A breath of fresh air for programming web apps in Julia.</strong>
</p>
<p align="center">
  <a href='https://app.travis-ci.com/ndortega/Oxygen.jl.svg?branch=master'><img src='https://app.travis-ci.com/ndortega/Oxygen.jl.svg?branch=master' alt='Build Passing' /></a>
  <a href='https://coveralls.io/github/ndortega/Oxygen.jl?branch=master'><img src='https://coveralls.io/repos/github/ndortega/Oxygen.jl/badge.svg?branch=master&version=1.0' alt='Coverage Status' /></a>
</p>

## About
Oxygen is a micro-framework built on top of the HTTP.jl library. 
Breath easy knowing you can quickly spin up a web server with abstractions you're already familiar with.

## Minimalistic Example

Create a web-server with very few lines of code
```julia
using Oxygen
using HTTP

@get "/greet" function(req::HTTP.Request)
    return "hello world!"
end

# start the web server
serve()
```

## Path parameters

Path parameters are declared with braces and are passed directly to your request handler. 
```julia
using Oxygen
using HTTP

# use path params without type definitions (defaults to Strings)
@get "/add/{a}/{b}" function(req, a, b)
    return parse(Float64, a) + parse(Float64, b)
end

# use path params with type definitions (they are automatically converted)
@get "/multiply/{a}/{b}" function(req, a::Float64, b::Float64)
    return a * b
end

# The order of the parameters doesn't matter (just the name matters)
@get "/subtract/{a}/{b}" function(req, b::Int64, a::Int64)
    return a - b
end

# start the web server
serve()
```

## Return JSON

All objects are automatically deserialized into JSON using the JSON3 library

```julia
using Oxygen
using HTTP

@get "/data" function(req::HTTP.Request)
    return Dict("message" => "hello!", "value" => 99.3)
end

# start the web server
serve()
```

## Deserialize & Serialize custom structs
Oxygen provides some out-of-the-box serialization & deserialization but requires the use of StructTypes when converting structs

```julia
using Oxygen
using HTTP
using StructTypes

struct Animal
    id::Int
    type::String
    name::String
end

# Add a supporting struct type definition so JSON3 can serialize & deserialize automatically
StructTypes.StructType(::Type{Animal}) = StructTypes.Struct()

@get "/get" function(req::HTTP.Request)
    # serialize struct into JSON automatically (because we used StructTypes)
    return Animal(1, "cat", "whiskers")
end

@post "/echo" function(req::HTTP.Request)
    # deserialize JSON from the request body into an Animal struct
    animal = json(req, Animal)
    # serialize struct back into JSON automatically (because we used StructTypes)
    return animal
end

# start the web server
serve()
```

## API Reference (macros)

#### @get, @post, @put, @patch, @delete
```julia
  @get(path, func)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `path` | `string` | **Required**. The route to register |
| `func` | `function` | **Required**. The request handler for this route |

Used to register a function to a specific endpoint to handle that corresponding type of request

#### @route
```julia
  @route(path, methods, func)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `path` | `string` | **Required**. The route to register |
| `methods` | `array` | **Required**. The types of HTTP requests to register to this route|
| `func` | `function` | **Required**. The request handler for this route |

Low-level macro that allows a route to be handle mulitiple request types


#### @staticfiles
```julia
  @staticfiles(folder, mount)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `folder` | `string` | **Required**. The folder to serve files from |
| `mountdir` | `string` | The root endpoint to mount files under (default is "static")|

Serve all static files within a folder. This function recursively searches a directory
and mounts all files under the mount directory using their relative paths.


### Request helper functions

#### html()
```julia
  html(content, status, headers)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `content` | `string` | **Required**. The string to be returned as HTML |
| `status` | `integer` | The HTTP response code (default is 200)|
| `headers` | `dict` | The headers for the HTTP response (default has contentype header set to "text/html; charset=utf-8") |

helper function to designate when content should be returned as HTML


#### queryparams()
```julia
  queryparams(request)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |

Returns the query parameters from a request as a Dict()

### Body Functions

#### text()
```julia
  text(request)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |

Returns the body of a request as a string

#### binary()
```julia
  binary(request)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |

Returns the body of a request as a binary file (returns a vector of Int8's)

#### json()
```julia
  json(request, classtype)
```
| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `req` | `HTTP.Request` | **Required**. The HTTP request object |
| `classtype` | `struct` | A struct to deserialize a JSON object into |

Deserialize the body of a request into a julia struct 