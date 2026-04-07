# Working with Sessions

Sessions allow you to persist user data (like login state, shopping carts, or preferences) across multiple HTTP requests. 

Oxygen provides a flexible architecture based on **Cookies** and **Application Context**, allowing you to implement the session strategy that best fits your needs.

> **See it in Action:**
> A complete, runnable example of the concepts below is available in your Oxygen installation under:
> `demo/sessiondemo.jl`

## The Session Architecture

Unlike frameworks that enforce a specific session database, Oxygen gives you the building blocks to build your own:

1.  **Transport:** An encrypted, HTTP-only Cookie holds the **Session ID**.
2.  **State:** An **Application Context** holds the actual data on the server (In-Memory, Database, etc.).

## 1. Defining the Session Store

First, we define a struct to hold our active sessions. We will inject this into our routes using Oxygen's **Application Context**.

### In-Memory Store (Default)
For development and simple tools, a Dictionary is sufficient.

```julia
using Oxygen, HTTP, UUIDs

# A simple container for active sessions
struct SessionStore
    data::Dict{String, Dict{String, Any}} 
end

# Helper to initialize
NewSessionStore() = SessionStore(Dict{String, Dict{String, Any}}())
```

### Note on Persistence
> **⚠️ Production Advice:** The in-memory example above loses data when the server restarts. 
> 
> **You can implement persistence today:** Simply replace the `Dict` in the `SessionStore` with a database connection (like Redis, PostgreSQL, or SQLite). Since you control the logic in the route handlers, you can swap `store.data[id]` with a database query (e.g., `DBInterface.execute(...)`).
>
> *Official plugins for automatic database persistence are planned for future releases.*

## 2. Configuring Security

Sessions rely on the browser returning a specific ID. To prevent users from tampering with this ID or hijacking sessions, we **must** enable encryption.

```julia
# Set a strong secret key for AES-256 encryption
configcookies(secret_key="my-super-secret-key-must-be-32-bytes")
```

## 3. Implementing the Logic

### Login (Create Session)

When a user logs in, we generate a unique ID, create an entry in our `SessionStore`, and send the ID to the user as an encrypted cookie.

Notice how we use `ctx::Context{SessionStore}` to access our application state.

```julia
@post "/login" function(req, ctx::Context{SessionStore})
    # 1. Logic to validate user credentials (omitted)
    user_email = "alice@example.com" 
    
    # 2. Generate a secure, random Session ID
    session_id = string(uuid4())
    
    # 3. Store user data in the server-side store
    ctx.payload.data[session_id] = Dict(
        "email" => user_email,
        "role" => "admin",
        "login_time" => time()
    )
    
    # 4. Set the encrypted session cookie
    res = Response("Login Successful")
    set_cookie!(res, "session_id", session_id, 
        encrypted=true, 
        httponly=true,  # Prevent JS access (XSS protection)
        maxage=3600     # Expire in 1 hour
    )
    
    return res
end
```

### Protected Route (Read Session)

To access session data, we read the cookie and look it up in our `SessionStore`.

```julia
@get "/dashboard" function(req, ctx::Context{SessionStore})
    # 1. Retrieve the Session ID from the cookie
    session_id = get_cookie(req, "session_id", encrypted=true)
    
    # 2. Access the store via Context
    store = ctx.payload.data
    
    # 3. Validate: Does the cookie exist? Is the session active?
    if isnothing(session_id) || !haskey(store, session_id)
        return Response(401, "Unauthorized - Please Login")
    end
    
    # 4. Retrieve the data
    user_data = store[session_id]
    
    return "Welcome back, $(user_data["email"])!"
end
```

### Logout (Destroy Session)

Proper logout requires removing the data from the server **and** invalidating the cookie on the client.

```julia
@post "/logout" function(req, ctx::Context{SessionStore})
    session_id = get_cookie(req, "session_id", encrypted=true)
    
    # 1. Remove data from the server
    if !isnothing(session_id)
        delete!(ctx.payload.data, session_id)
    end
    
    res = Response("Logged Out")
    
    # 2. Invalidate the cookie immediately (maxage=0)
    set_cookie!(res, "session_id", "", maxage=0)
    
    return res
end
```

## 4. Starting the Server

Finally, we initialize our `SessionStore` and pass it to the `serve` function. Oxygen automatically injects this instance into any route requesting `Context{SessionStore}`.

```julia
# Initialize the application state
app_state = NewSessionStore()

# Start the server with the context
serve(context=app_state)
```

## Summary Checklist

When implementing sessions, ensure you:

* [ ] Use `httponly=true` for the session cookie to prevent XSS attacks.
* [ ] Use `encrypted=true` so users cannot spoof their Session ID.
* [ ] Use **Application Context** (`serve(context=...)`) instead of global variables.
* [ ] Clean up server-side data upon logout.