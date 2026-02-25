module SessionDemo

using Oxygen
using HTTP
using Base64
using UUIDs

# ==============================================================================
# 1. State Definition (Application Context)
# ==============================================================================

# We define a struct to hold our application state.
struct SessionStore
    # Mapping: SessionID -> Username
    data::Dict{String, String}
end

# Helper to create a new empty store
NewSessionStore() = SessionStore(Dict{String, String}())

# Enable encryption keys for cookies
configcookies(secret_key="my-super-secret-key-123456")

# Test credentials
const TEST_USER = "admin"
const TEST_PASS = "1234"

# ==============================================================================
# 2. Views (HTML Generators)
# ==============================================================================

function login_page(error_msg="")
    err_html = isempty(error_msg) ? "" : "<p style='color:red; font-weight:bold'>$error_msg</p>"
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>Login - Session Demo</title>
    </head>
    <body style="font-family: sans-serif; display:flex; justify-content:center; padding-top:50px; background:#f0f2f5;">
        <div style="background:white; padding:30px; border-radius:8px; box-shadow:0 2px 10px rgba(0,0,0,0.1); width: 300px;">
            <h2 style="text-align:center; color:#1a73e8;">🔐 Restricted Access</h2>
            $err_html
            <form action="/login" method="POST" style="display:flex; flex-direction:column; gap:15px;">
                <input type="text" name="user" placeholder="User (admin)" required style="padding:10px; border:1px solid #ddd; border-radius:4px;">
                <input type="password" name="pass" placeholder="Password (1234)" required style="padding:10px; border:1px solid #ddd; border-radius:4px;">
                <button type="submit" style="padding:10px; background:#1a73e8; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">Sign In</button>
            </form>
            <p style="font-size:12px; color:#666; text-align:center; margin-top:20px;">Use: admin / 1234</p>
        </div>
    </body>
    </html>
    """
end

function dashboard_page(username)
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>Dashboard</title>
    </head>
    <body style="font-family: sans-serif; background:#e8f0fe; padding:50px; text-align:center;">
        <div style="background:white; padding:40px; border-radius:12px; display:inline-block; box-shadow:0 4px 20px rgba(0,0,0,0.1);">
            <h1 style="color:#1e8e3e;">👋 Welcome, $(username)!</h1>
            <p>You are logged in and your session is secure.</p>
            <p>Try reloading the page — you will stay logged in.</p>
            <br>
            <form action="/logout" method="POST">
                <button type="submit" style="padding:10px 20px; background:#d93025; color:white; border:none; border-radius:4px; cursor:pointer;">Log Out</button>
            </form>
        </div>
    </body>
    </html>
    """
end

# ==============================================================================
# 3. Routes and Logic
# ==============================================================================

# NOTE: We use `ctx::Context{SessionStore}` to extract the application state.
# The actual struct is accessed via `ctx.payload`.

@get "/" function(req, ctx::Context{SessionStore})
    store = ctx.payload
    session_id = get_cookie(req, "session_id", encrypted=true)
    
    # Check if session exists in our injected store
    if !isnothing(session_id) && haskey(store.data, session_id)
        return Response(303, ["Location" => "/dashboard"])
    end
    return html(login_page())
end

@post "/login" function(req, ctx::Context{SessionStore})
    store = ctx.payload
    # Parse body content
    data = String(req.body)
    
    # Authenticate (Dummy logic)
    if contains(data, "user=$TEST_USER") && contains(data, "pass=$TEST_PASS")
        new_session_id = string(uuid4())
        
        # Save to the injected store
        store.data[new_session_id] = TEST_USER
        
        res = Response(303, ["Location" => "/dashboard"])
        
        # Set encrypted cookie
        set_cookie!(res, "session_id", new_session_id, encrypted=true, httponly=true, maxage=3600)
        return res
    else
        return html(login_page("Invalid username or password!"))
    end
end

@get "/dashboard" function(req, ctx::Context{SessionStore})
    store = ctx.payload
    session_id = get_cookie(req, "session_id", encrypted=true)
    
    # Verify session against the store
    if isnothing(session_id) || !haskey(store.data, session_id)
        return Response(303, ["Location" => "/"]) 
    end
    
    username = store.data[session_id]
    return html(dashboard_page(username))
end

@post "/logout" function(req, ctx::Context{SessionStore})
    store = ctx.payload
    session_id = get_cookie(req, "session_id", encrypted=true)
    
    if !isnothing(session_id)
        # Remove from the store
        delete!(store.data, session_id)
    end
    
    res = Response(303, ["Location" => "/"])
    set_cookie!(res, "session_id", "", maxage=0) # Clear cookie
    return res
end

# ==============================================================================
# 4. Server Startup
# ==============================================================================

# Initialize the application state
app_state = NewSessionStore()

println("Starting Session Demo on http://localhost:6060")
println("Admin User: $TEST_USER / $TEST_PASS")

# Pass the state object to the 'context' parameter
# This object will be injected into routes requesting Context{SessionStore}
serve(port=6060, context=app_state)

end