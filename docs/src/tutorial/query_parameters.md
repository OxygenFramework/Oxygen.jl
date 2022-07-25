# Query Parameters

When you declare other function parameters that are not part of the path parameters, they are automatically interpreted as "query" parameters.

In the example below, we have two query parameters passed to our request handler
1. debug = true 
2. limit = 10

```
http://127.0.0.1:8000/echo?debug=true&limit=10
```

To show how this works, lets take a look at this route below:

```julia
@get "/echo" function(req)
    # the queryparams() function will extract all query paramaters from the url 
    return queryparams(req)
end
```

If we hit this route with a url like the one below we should see the query parameters returned as a JSON object 

```
{
    "debug": "true",
    "limit": "10"
}
```

The important distinction between `query parameters` and `path parameters` is that they are not automatically converted for you. In this example `debug` & `limit` are set to a string even though those aren't the "correct" data types.