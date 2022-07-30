

# OAuth2 with Umbrella.jl

[Umbrella.jl](https://github.com/jiachengzhang1/Umbrella.jl) is a simple Julia authentication plugin, it supports Google and GitHub OAuth2 with more to come. Umbrella integrates with Julia web framework such as [Genie.jl](https://github.com/GenieFramework/Genie.jl), [Oxygen.jl](https://github.com/ndortega/Oxygen.jl) or [Mux.jl](https://github.com/JuliaWeb/Mux.jl) effortlessly.

## Prerequisite
Before using the plugin, you need to obtain OAuth 2 credentials, see [Google Identity Step 1](https://developers.google.com/identity/protocols/oauth2#1.-obtain-oauth-2.0-credentials-from-the-dynamic_data.setvar.console_name-.), [GitHub: Creating an OAuth App](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app) for details.

## Installation

```julia
pkg> add Umbrella
```
## Basic Usage

Many resources are available describing how OAuth 2 works, please advice [OAuth 2.0](https://oauth.net/2/), [Google Identity](https://developers.google.com/identity/protocols/oauth2/web-server#obtainingaccesstokens), or [GitHub OAuth 2](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app) for details

Follow the steps below to enable OAuth 2 in your application. 

### 1. Configuration

OAuth 2 required parameters such as `client_id`, `client_secret` and `redirect_uri` need to be configured through `Configuration.Options`. 

`scopes` is a list of resources the application will access on user's behalf, it is vary from one provider to another.

`providerOptions` configures the additional parameters at the redirection step, it is dependent on the provider.

```julia
const options = Configuration.Options(;
    client_id = "", # client id from an OAuth 2 provider
    client_secret = "", # secret from an OAuth 2 provider
    redirect_uri = "http://localhost:3000/oauth2/google/callback",
    success_redirect = "/protected",
    failure_redirect = "/error",
    scopes = ["profile", "openid", "email"],
    providerOptions = GoogleOptions(access_type="online")
)
```

`init` function takes the provider and options, then returns an OAuth 2 instance. Available provider values are `:google`, `:github` and `facebook`. This list is growing as more providers are supported.

```julia
oauth2_instance = init(:google, options)
```

The examples will use [Oxygen.jl](https://github.com/ndortega/Oxygen.jl) as the web framework, but the concept is the same for other web frameworks.

### 2. Handle provider redirection

Create two endpoints,

- `/` serve the login page which, in this case, is a Google OAuth 2 link.
- `/oauth2/google` handles redirections to an OAuth 2 server.

```julia
@get "/" function ()
  return "<a href='/oauth2/google'>Authenticate with Google</a>"
end

@get "/oauth2/google" function ()
  oauth2_instance.redirect()
end
```

`redirect` function generates the URL using the parameters in step 1, and redirects users to provider's OAuth 2 server to initiate the authentication and authorization process.

Once the users consent to grant access to one or more scopes requested by the application, OAuth 2 server responds the `code` for retrieving access token to a callback endpoint.

### 3. Retrieves tokens

Finally, create the endpoint handling callback from the OAuth 2 server. The path must be identical to the path in `redirect_uri` from `Configuration.Options`.

`token_exchange` function performs two actions,
1. Use `code` responded by the OAuth 2 server to exchange an access token.
2. Get user profile using the access token.

A handler is required for access/refresh tokens and user profile handling.

```julia
@get "/oauth2/google/callback" function (req)
  query_params = queryparams(req)
  code = query_params["code"]

  oauth2_instance.token_exchange(code, function (tokens, user)
      # handle tokens and user profile here
    end
  )
end
```


## Full Example

```julia
using Oxygen
using Umbrella
using HTTP

const oauth_path = "/oauth2/google"
const oauth_callback = "/oauth2/google/callback"

const options = Configuration.Options(;
    client_id="", # client id from Google API Console
    client_secret="", # secret from Google API Console
    redirect_uri="http://127.0.0.1:8080$(oauth_callback)",
    success_redirect="/protected",
    failure_redirect="/no",
    scopes=["profile", "openid", "email"]
)

const google_oauth2 = Umbrella.init(:google, options)

@get "/" function()
  return "<a href='$(oauth_path)'>Authenticate with Google</a>"
end

@get oauth_path function()
  # this handles the Google oauth2 redirect in the background
  google_oauth2.redirect()
end

@get oauth_callback function(req)
  query_params = queryparams(req)
  code = query_params["code"]

  # handle tokens and user details
  google_oauth2.token_exchange(code, 
    function (tokens::Google.Tokens, user::Google.User)
      println(tokens.access_token)
      println(tokens.refresh_token)
      println(user.email)
    end
  )
end

@get "/protected" function()
  "Congrets, You signed in Successfully!"
end

# start the web server
serve()
```