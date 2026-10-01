# Protocol revision identity. Included into the `MCP` module by `../mcp.jl`.
#
# Every revision the server understands is a `Val` singleton, so behavior is
# selected by dispatch (`f(spec::Val)`) and never by a runtime lookup table.
# Identity (version string + rank) for every revision lives here; behavior
# deltas live in the matching `vYYYY_MM_DD.jl` file, so each protocol stays
# isolated from the others and adding a revision never touches an existing
# revision's file (a revision with no deltas needs no file). See `strategy.jl`
# for the capability interface.

# ----------------------------------------------------------------------------
# Revision constants
# ----------------------------------------------------------------------------

const V2024_11_05 = Val(:v2024_11_05)
const V2025_03_26 = Val(:v2025_03_26)
const V2025_06_18 = Val(:v2025_06_18)
const V2025_11_25 = Val(:v2025_11_25)
const V2026_07_28 = Val(:v2026_07_28)

# Advertised order: modern revisions first, then legacy newest-first. This is
# the order `server/discover` reports and the order session negotiation scans.
const MODERN_SPECS = (V2026_07_28,)
const LEGACY_SPECS = (V2025_11_25, V2025_06_18, V2025_03_26, V2024_11_05)
const SUPPORTED_SPECS = (MODERN_SPECS..., LEGACY_SPECS...)

const LATEST_MODERN_SPEC = V2026_07_28
const LATEST_LEGACY_SPEC = V2025_11_25

# ----------------------------------------------------------------------------
# Identity
# ----------------------------------------------------------------------------

version_string(::Val{:v2024_11_05})::String = "2024-11-05"
version_string(::Val{:v2025_03_26})::String = "2025-03-26"
version_string(::Val{:v2025_06_18})::String = "2025-06-18"
version_string(::Val{:v2025_11_25})::String = "2025-11-25"
version_string(::Val{:v2026_07_28})::String = "2026-07-28"

# Revision order. Feature introductions are expressed as `spec_at_least`
# against the introduction's revision, so a new revision only declares its rank.
spec_rank(::Val{:v2024_11_05})::Int = 1
spec_rank(::Val{:v2025_03_26})::Int = 2
spec_rank(::Val{:v2025_06_18})::Int = 3
spec_rank(::Val{:v2025_11_25})::Int = 4
spec_rank(::Val{:v2026_07_28})::Int = 5

spec_at_least(a::Val, b::Val)::Bool = spec_rank(a) >= spec_rank(b)

# ----------------------------------------------------------------------------
# Classification
# ----------------------------------------------------------------------------

# Whether a revision belongs to the modern, stateless era. Only the modern
# spec overrides this; every legacy revision uses the default.
is_modern(::Val)::Bool = false
is_legacy(spec::Val)::Bool = !is_modern(spec)

"""
    spec_from_version(version) :: Union{Nothing,Val}

Map a wire protocol version string to its revision, or `nothing` when this
server does not support it. The chain is made of compile-time constants (no
runtime map); a new revision adds one line here plus its identity above.
"""
function spec_from_version(version::AbstractString)
    version == "2024-11-05" && return V2024_11_05
    version == "2025-03-26" && return V2025_03_26
    version == "2025-06-18" && return V2025_06_18
    version == "2025-11-25" && return V2025_11_25
    version == "2026-07-28" && return V2026_07_28
    return nothing
end

# Resolve a negotiated wire version to its revision, falling back to the latest
# legacy revision for an unknown value (mirroring `negotiate_version`). Used
# while call sites still hold wire strings instead of specs.
spec_or_latest_legacy(version::AbstractString) =
    something(spec_from_version(version), LATEST_LEGACY_SPEC)
