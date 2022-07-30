# Request Types 

When designing an API you need to first think about what `type` of requests
and what `routes` or `paths` your api would need to function. 

For example, if we were to design a weather app we'd probably want a way to lookup weather alerts for a particular state

```
http://localhost:8080/weather/alerts/{state}
```

This url can be broken down into several parts 
- `host` &rarr; `http://localhost`
- `port` &rarr; `8080`
- `route` or `path` &rarr; `/weather/alerts/{state}`
- `path parameter` &rarr; `{state}`

Before we start writing code for we need to answer some questions: 
1. What kind of data manipulation is this route going to perform?
    - Are we adding/removing/updating data? (This determines our http method)
2. Will this endpoint need any inputs?
    - If so, will we need to pass them through the path or inside the body of the http request?

This is when knowing the different type of http methods comes in handy.

Common HTTP methods:

- POST &rarr; when you want to **create** some data
- GET &rarr; when you want to **get** data
- PUT &rarr; **update** some data if it already exists or **create** it
- PATCH &rarr; when you want to **update** some data
- DELETE &rarr; when you want to **delete** some data

(there are more methods that aren't in this list)

In the HTTP protocol, you can communicate to each path using one (or more) of these "methods".

In reality you can use any of these http methods to do any of those operations. But it's heavily recommended to use the appropriate http method so that people & machines can easily understand your web api. 

Now back to our web example. Lets answer those questions:

1. This endpoint will return alerts from the US National Weather service api
2. The only input we will need is the state abbreviation

Since we will only be fetching data and not creating/updating/deleting anything, that means we will want to setup a `GET` route for our api to handle this type of action.

```julia
using Oxygen
using HTTP

@get "/weather/alerts/{state}" function(req::HTTP.Request, state::String)
    return HTTP.get("https://api.weather.gov/alerts/active?area=$state")
end

serve() 
```

With our code in place, we can run this code and visit the endpoint in our browser to view the alerts. Try it out yourself by clicking on the link below. 

http://127.0.0.1:8080/weather/alerts/NY
