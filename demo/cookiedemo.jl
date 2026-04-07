module CookieDemo

using Oxygen
using HTTP
using Dates

# Enable cookie support (encryption optional, disabled here for simplicity)
configcookies(secret_key="secret-key-para-demo")

# Simple HTML helper
function render_page(theme)
    color = theme == "dark" ? "#333" : "#fff"
    text_color = theme == "dark" ? "#fff" : "#333"
    
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Oxygen Cookie Demo</title>
        <style>
            body { font-family: sans-serif; background-color: $color; color: $text_color; display: flex; justify-content: center; align-items: center; height: 100vh; transition: background 0.3s; }
            .card { border: 1px solid #ccc; padding: 2rem; border-radius: 8px; background: rgba(255,255,255,0.1); text-align: center; }
            button { padding: 10px 20px; cursor: pointer; font-size: 1rem; border-radius: 5px; border: none; }
            .btn-dark { background: #333; color: #fff; border: 1px solid #fff; }
            .btn-light { background: #eee; color: #333; }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>🎨 Theme Preference</h1>
            <p>The current theme is: <strong>$theme</strong></p>
            <p>This is persisted via cookies!</p>
            <br>
            <form action="/set-theme" method="POST">
                <button type="submit" name="theme" value="light" class="btn-light">☀️ Light Mode</button>
                <button type="submit" name="theme" value="dark" class="btn-dark">🌙 Dark Mode</button>
            </form>
        </div>
    </body>
    </html>
    """
end

@get "/" function(req)
    # Try to read the 'theme' cookie, use 'light' as the default if not present
    current_theme = get_cookie(req, "theme", default="light", encrypted=false)
    return html(render_page(current_theme))
end

@post "/set-theme" function(req)
    # Get the form value
    form_data = queryparams(req) # or json(req) depending on how the form submits; standard HTML forms send a query string in the body if x-www-form-urlencoded — simplifying here
    
    # In a simple POST form, Oxygen places it in the body.
    # To simplify the demo without form parsing, we'll assume it comes from the URL as if it were a GET,
    # or assume we extract it from the body manually.
    # Let's make it easy: use a query param in the link to keep the demo compact
    
    new_theme = get(form_data, "theme", "light") 
    
    # Create the response
    res = Response(303, ["Location" => "/"]) # Redirect
    
    # Set the cookie
    set_cookie!(res, "theme", new_theme, maxage=60*60*24*365, encrypted=false) # 1 year
    
    return res
end

# Auxiliary route to process the POST form (workaround for a quick demo without form middleware)
@post "/set-theme" function(req)
    # Extract from raw body (e.g. theme=dark)
    body_str = String(req.body)
    new_theme = contains(body_str, "dark") ? "dark" : "light"
    
    res = Response(303, ["Location" => "/"])
    set_cookie!(res, "theme", new_theme, maxage=3600, encrypted=false)
    return res
end

serve(port=6060)

end