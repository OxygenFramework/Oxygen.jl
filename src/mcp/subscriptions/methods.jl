# Method routing for subscriptions and resource subscriptions.
# Included into `MCP.Subscriptions` by `../subscriptions.jl`.

# ----------------------------------------------------------------------------
# Method routing
# ----------------------------------------------------------------------------

# `subscriptions/listen` is modern-only, the resource subscriptions
# legacy-only; `method_available` gates each to its era before dispatch.
handle_method(spec::Val, ::Val{:subscriptions_listen}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session::Union{Nothing,MCPSession}=nothing) =
    listen_call(ctx, req, id, params)

handle_method(spec::Val, ::Val{:resources_subscribe}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session::Union{Nothing,MCPSession}=nothing) =
    subscribe_resource_legacy(ctx, id, params; session=session)

handle_method(spec::Val, ::Val{:resources_unsubscribe}, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
              id, params, raw::String; session::Union{Nothing,MCPSession}=nothing) =
    unsubscribe_resource_legacy(ctx, id, params; session=session)
