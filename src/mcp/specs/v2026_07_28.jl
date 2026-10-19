# 2026-07-28: the modern, stateless revision. Complete profile; the behavior
# only this revision customizes lives in `specs/behaviors.jl`, included after
# the version registry has been built.

@spec Val(:v2026_07_28) begin
    version_string           = "2026-07-28"
    spec_rank                = 5
    is_modern                = true
    uses_sessions            = false
    allows_batch             = false
    emits_structured_content = true
    shows_resource_icons     = true
    get_policy               = :reject
    delete_policy            = :reject
    not_found_code           = MCP_INVALID_PARAMS
end
