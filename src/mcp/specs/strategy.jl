# The protocol strategy interface: every behavior the spec-agnostic core asks
# the active revision about. Included into the `MCP` module by `../mcp.jl`,
# before the spec delta files.
#
# This file holds the defaults (the "abstract class"); a revision overrides a
# function in its own `vYYYY_MM_DD.jl` only when its behavior differs. Feature
# introductions are expressed with `spec_at_least`, so they need no per-revision
# code at all. Nothing here looks a revision up at runtime: every function
# dispatches on the `Val` the caller already holds.

# ----------------------------------------------------------------------------
# Admission / transport policy
# ----------------------------------------------------------------------------

# Whether JSON-RPC batches are accepted. Batching existed only in 2025-03-26.
allows_batch(::Val)::Bool = false

# Whether the revision keeps per-client sessions. Modern revisions are stateless.
uses_sessions(::Val)::Bool = true

# What a GET on the MCP endpoint does: `:legacy_sse` serves the legacy
# notification stream / health body; `:reject` answers 405.
get_policy(::Val)::Symbol = :legacy_sse

# What a DELETE on the MCP endpoint does: `:session` terminates the named
# legacy session; `:reject` answers 405.
delete_policy(::Val)::Symbol = :session

# Per-request validation beyond the JSON-RPC envelope. The modern revision
# enforces `_meta` fields and mirrored headers; legacy requests skip all of it.
validate_request(::Val, ctx::ServerContext, req::Union{Nothing,HTTP.Request},
                 method::String, params) = nothing

# ----------------------------------------------------------------------------
# Result shaping
# ----------------------------------------------------------------------------

# Wrap a successful result in the revision's envelope. Modern results carry
# `resultType` and the server identity in `_meta`; legacy results are untouched.
result_envelope(::Val, ctx::ServerContext, result) = result

# Add the revision's list/read cache hints to a result. `scope` is the cache
# scope ("public" for lists, "private" for resource reads).
with_cache_hints(::Val, result; scope::String="public") = result

# The JSON-RPC code a missing resource gets. Modern folded not-found into
# `-32602`; the legacy revisions defined the dedicated `-32002`.
not_found_code(::Val)::Int = MCP_RESOURCE_NOT_FOUND

# Feature introductions: `structuredContent` tool results and resource icons
# both arrived in 2025-06-18, so the introduction is the only fact worth
# encoding and `spec_at_least` derives every revision from it.
emits_structured_content(spec::Val)::Bool = spec_at_least(spec, V2025_06_18)
shows_resource_icons(spec::Val)::Bool = spec_at_least(spec, V2025_06_18)

# ----------------------------------------------------------------------------
# Method surface
# ----------------------------------------------------------------------------

# Whether a revision serves a method at all. Shared methods default to true;
# the six era-exclusive methods name their era here, once. The handler for an
# unavailable method is never reached: dispatch answers `-32601` first.
method_available(::Val, ::Val)::Bool = true
method_available(spec::Val, ::Val{:initialize})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:ping})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:resources_subscribe})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:resources_unsubscribe})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:server_discover})::Bool = is_modern(spec)
method_available(spec::Val, ::Val{:subscriptions_listen})::Bool = is_modern(spec)
