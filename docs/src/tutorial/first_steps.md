# First Steps

In this tutorial, you'll learn about all the core features of Oxygen ia a simple step-by-step approach.
This guide will be aimed at beginner/intermediate users and will gradually build upon each other. 

# Setup your first project

Navigate to your projects folder (If you're using and editor like vscode, just open up your project folder

`cd /path/to/your/project`

Open open a terminal and start the julia repl with this command

```
julia
```

Before we go any further, lets create a new environment for this project.
Press the `]` key inside the repl to use Pkg (julia's jult in package manager) 
you should see something similar to `(v1.7) pkg>` in the repl

Activate your current environment 

```
pkg> activate .
```

Install the latest version of Oxygen and HTTP

```
pkg> add Oxygen HTTP
```

Press the backspace button to exit the package manager and return to the julia repl

If everything was done correctly, you should see a `Project.toml` and `Manifest.toml` 
file created in your project folder

Next lets create our `src` folder and our `main.jl` file. Once that's complete, our project 
should ook something like this.

```
project
├── src
│   ├── main.jl
├── Project.toml
├── Manifest.toml

```

For the duration of this guide, we will be working out of the `src/main.jl` file 

# Creating your first web server

Here's an example of what a simple Oxygen server could look like

```julia
module Main 
using Oxygen
using HTTP

@get "/greet" function(req::HTTP.Request)
    return "hello world!"
end

serve()
end
```

Start the webserver with:

```julia
include("src/main.jl")
```

# Line by line

```julia
using Oxygen
using HTTP
```

Here we pull in the both libraries our api depends on. The `@get` macro and `serve()` function come from Oxygen
and the `HTTP.Request` type comes from the HTTP library.

Next we move into the core snippet where we define a route for our api. This route is made up of several components.
- http method  => from `@get` macro (it's a GET request)
- path => the endpoint that will get added to our api which is `"/greet"`
- request handler => The function that accepts a request and returns a response

```julia
@get "/greet" function(req::HTTP.Request)
    return "hello world!"
end
```

Finally at the bottom of our `Main` module we have this function to start up our brand new webserver.
This function can take a number of keyword arguments such as the `host` & `port`, which can be helpful if you don't want to use the default values.

```julia
serve()
```

For example, you can start your server on port `8000` instead of `8080` which is used by default
```julia
serve(port=8000)
```

# Try out your endpoints

You should see the server starting up inside the console. 
You should be able to hit `http://127.0.0.1:8080/greet` inside your browser and see the following:
```
"hello world!"
```


# Interactive API documenation

Open your browser to http://127.0.0.1:8080/docs
Here you'll see the auto-generated documentation for your api. 
This is done internally by generating a JSON object that conforms to the openapi format. 
Once generated, you can feed this same schema to libraries like swagger which translate this 
into an interactive api for you to explore.