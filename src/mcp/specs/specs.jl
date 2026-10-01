# Protocol revision identity and ordering. Included into the `MCP` module by
# `../mcp.jl`, before the revision files.
#
# Every revision is a `Val` singleton, so capabilities and behavior are
# selected by dispatch (`f(spec::Val)`) and never by a runtime lookup table.
# A revision's full profile (identity included) is declared explicitly in its
# own `vYYYY_MM_DD.jl` file with `@spec`; `spec_from_version` parses the wire
# string back to the singleton. See `strategy.jl` for the interface.

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
# Ordering / classification
# ----------------------------------------------------------------------------

# Revision order only (ordering, negotiation). Capabilities are not derived
# from rank: each revision declares them explicitly in its profile.
spec_at_least(a::Val, b::Val)::Bool = spec_rank(a) >= spec_rank(b)

# Legacy is the complement of modern; `is_modern` is part of each revision's
# `@spec` profile.
is_legacy(spec::Val)::Bool = !is_modern(spec)

# ----------------------------------------------------------------------------
# Wire parsing
# ----------------------------------------------------------------------------

"""
    spec_from_version(version) :: Union{Nothing,Val}

Map a wire protocol version string to its revision, or `nothing` when this
server does not support it. The mapping is derived from `SUPPORTED_SPECS` and
each revision's declared `version_string`, so adding a revision never requires
a second ladder to keep in sync: the constant, the `@spec` profile, and the
include are the only edits.
"""
function spec_from_version(version::AbstractString)
    for spec in SUPPORTED_SPECS
        version_string(spec) == version && return spec
    end
    return nothing
end

# Resolve a negotiated wire version to its revision, falling back to the latest
# legacy revision for an unknown value (mirroring `negotiate_version`). Used
# while call sites still hold wire strings instead of specs.
spec_or_latest_legacy(version::AbstractString) =
    something(spec_from_version(version), LATEST_LEGACY_SPEC)
