# 2025-11-25 — the latest legacy revision. Complete profile, nothing inherited.

@spec Val(:v2025_11_25) begin
    version_string           = "2025-11-25"
    spec_rank                = 4
    is_modern                = false
    uses_sessions            = true
    allows_batch             = false
    emits_structured_content = true
    shows_resource_icons     = true
    get_policy               = :legacy_sse
    delete_policy            = :session
    not_found_code           = MCP_RESOURCE_NOT_FOUND
end
