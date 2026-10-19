# Protocol revision registry: traits, profiles, derived version lists, and
# negotiation. This is a shared contract module: it deliberately depends only on
# the leaf modules (errors, envelopes, headers) and `AppContext`, never on a
# domain or transport.

module Specs

using HTTP

using ...AppContext: ServerContext

using ..Errors: MCPRequestError, MCP_INVALID_PARAMS, MCP_RESOURCE_NOT_FOUND, MCP_UNSUPPORTED_PROTOCOL_VERSION, MCP_HEADER_MISMATCH
using ..Envelopes: META_KEY, META_PROTOCOL, META_CLIENT_CAPABILITIES, LIST_TTL_MS, modern_envelope
using ..Headers: required_header, decode_header_value

export @spec

include("specs/specs.jl")            # revision constants, wire parsing
include("specs/strategy.jl")         # @spec macro, neutral behaviors, method surface
include("specs/v2024_11_05.jl")      # complete revision profile
include("specs/v2025_03_26.jl")
include("specs/v2025_06_18.jl")
include("specs/v2025_11_25.jl")
include("specs/v2026_07_28.jl")

# ----------------------------------------------------------------------------
# Derived version lists
# ----------------------------------------------------------------------------
# Defined after the revision profiles: `version_string` is one method per
# revision, so the lists can only be materialized once every file is loaded.

# This server is dual-era: it serves the modern, stateless revision and the
# legacy initialize-handshake revisions that mainstream clients speak. Era is a
# property of the request (its `_meta` or method), not the transport. Every list
# is derived from the spec registry, the single source of truth.
const MODERN_VERSIONS = [version_string(spec) for spec in MODERN_SPECS]
const LATEST_MODERN_VERSION = version_string(LATEST_MODERN_SPEC)

# Legacy (initialize-handshake) revisions, newest first.
const LEGACY_VERSIONS = [version_string(spec) for spec in LEGACY_SPECS]
const LATEST_LEGACY = version_string(LATEST_LEGACY_SPEC)

# Kept for backwards compatibility: the latest modern revision is the protocol
# version advertised by the stateless path.
const PROTOCOL_VERSION = LATEST_MODERN_VERSION

# Every revision this server understands, across both eras (advertised by
# `server/discover` and returned in unsupported-version errors).
const SUPPORTED_VERSIONS = [version_string(spec) for spec in SUPPORTED_SPECS]

"""
    negotiate_version(client_version) :: String

Negotiate the protocol version for a legacy `initialize` handshake: echo the
client's version when it is a supported legacy revision, otherwise fall back to
the latest legacy revision and let the client decide whether it can proceed.
"""
function negotiate_version(client_version::Union{Nothing,AbstractString})::String
    if !isnothing(client_version)
        spec = spec_from_version(client_version)
        if !isnothing(spec) && is_legacy(spec)
            return version_string(spec)
        end
    end
    return LATEST_LEGACY
end

# Behavioral overrides for the modern revision (they read the constants above).
include("specs/behaviors.jl")

end # module Specs
