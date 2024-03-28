# Request Body 

Whenever you need to send data from a client to your API,  you send it as a request body.

A request body is data sent by the client to your API (usually JSON). A response body is the data your API sends to the client.

Request bodies are useful when you need to send more complicated information
to an API. Imagine we wanted to request an uber/lyft to come pick us up. The app (a client) will have to send a lot of information to make this happen. It'd need to send information about the user (like location data, membership info) and data about the destination. The api in turn will have to figure out pricing, available drivers and potential routes to take. 

The inputs of this api are pretty complicated which means it's a perfect case where we'd want to use the request body to send this information. You could send this kind of information through the URL, but I'd highly recommend you don't. Request bodies can store data in pretty much any format which is a lot more flexible than what a URL can support.


## Example

The request bodies can be read and converted to a Julia object by using the built-in `json()` helper function. 

```julia
struct Person
    name::String
    age::String
end

@post "/create/struct" function(req)
    # this will convert the request body directly into a Person struct
    person = json(req, Person)
    return "hello $(person.name)!"
end

@post "/create/dict" function(req)
    # this will convert the request body into a Julia Dict
    data = json(req)
    return """hello $(data["name"])!"""
end
```

When converting JSON into struct's Oxygen will throw an error if the request body doesn't match the struct, all properties need to be visible and match the right type. 

If you don't pass a struct to convert the JSON into, then it will convert the JSON into a Julia Dictionary. This has the benefit of being able to take JSON of any shape which is helpful when your data can change shape or is unknown. 
