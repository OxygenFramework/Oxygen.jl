# 2025-06-18 — the revision that introduced `structuredContent` tool results
# and resource icons. Complete profile, nothing inherited.

@spec Val(:v2025_06_18) begin
    version_string           = "2025-06-18"
    spec_rank                = 3
    is_modern                = false
    uses_sessions            = true
    allows_batch             = false
    emits_structured_content = true
    shows_resource_icons     = true
    get_policy               = :legacy_sse
    delete_policy            = :session
    not_found_code           = MCP_RESOURCE_NOT_FOUND
end
