# 2025-03-26 — the revision that added JSON-RPC batching (removed again in
# 2025-06-18). Complete profile, nothing inherited.

@spec Val(:v2025_03_26) begin
    version_string           = "2025-03-26"
    spec_rank                = 2
    is_modern                = false
    uses_sessions            = true
    allows_batch             = true
    emits_structured_content = false
    shows_resource_icons     = false
    get_policy               = :legacy_sse
    delete_policy            = :session
    not_found_code           = MCP_RESOURCE_NOT_FOUND
end
