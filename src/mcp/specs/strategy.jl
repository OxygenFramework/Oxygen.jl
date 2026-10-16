# The protocol strategy interface: every capability and behavior the
# spec-agnostic core asks the active revision about. Included into the `MCP`
# module by `../mcp.jl`, before the revision files.
#
# Each revision declares its *complete* profile with an `@spec` block in its own
# `vYYYY_MM_DD.jl` file; nothing is inherited and `@spec` rejects unknown,
# duplicated, or omitted capabilities at expansion time, so a spec file is the
# readable source of truth for what that revision supports. (The profile
# functions have no fallback methods on purpose: a missing capability must fail
# loudly while loading, not with a `MethodError` deep in a request.) This file
# holds only:
#
#   * `SPEC_TRAIT_TYPES`, the complete profile contract, and the `@spec` macro
#     that turns a declaration block into typed interface methods;
#   * the neutral result-pipeline behaviors (a revision overrides them only when
#     it changes results, so their no-op defaults are not capabilities);
#   * the structural method surface, which is a fact about the revision
#     families, not per-revision data.
#
# ----------------------------------------------------------------------------
# @spec: declare a revision's complete capability profile
# ----------------------------------------------------------------------------

# The module the interface functions live in. Captured where the macro is
# defined so `@spec` extends these functions even when invoked from another
# module (tests, clients).
const SPEC_MODULE = @__MODULE__

# The complete profile contract: every key a `@spec` block must declare, with
# the type its interface method returns. Keeping the list here (rather than in
# prose) lets `@spec` reject unknown, duplicated, and omitted capabilities at
# expansion time. Descriptions:
#
#   version_string           wire version, e.g. "2025-06-18"
#   spec_rank                ordering only, e.g. 3
#   is_modern                true only for the stateless era
#   uses_sessions            whether requests resolve per-client sessions
#   allows_batch             whether JSON-RPC batches are accepted
#   emits_structured_content whether tool results carry structuredContent
#   shows_resource_icons     whether resource entries carry icons
#   get_policy               :legacy_sse (serve) or :reject (405)
#   delete_policy            :session (terminate) or :reject (405)
#   not_found_code           missing-resource JSON-RPC code
const SPEC_TRAIT_TYPES = (
    version_string           = String,
    spec_rank                = Int,
    is_modern                = Bool,
    uses_sessions            = Bool,
    allows_batch             = Bool,
    emits_structured_content = Bool,
    shows_resource_icons     = Bool,
    get_policy               = Symbol,
    delete_policy            = Symbol,
    not_found_code           = Int,
)

"""
    @spec Val(:vYYYY_MM_DD) begin
        version_string = "..."
        spec_rank      = n
        ...
    end

Declare a revision's complete capability profile, defining one typed interface
method per key (`version_string(::Val{:vYYYY_MM_DD})::String`, ...). Every key
of `SPEC_TRAIT_TYPES` must appear exactly once: unknown, duplicated, or omitted
keys are expansion-time errors, so a typo cannot silently become a new function
or a half-declared revision.

Nothing is inherited, so a revision that omitted a capability would otherwise
fail with a `MethodError` during a request; the profile is validated up front
instead. External modules declare revisions with `MCP.@spec`; values resolve in
the calling module, so refer to server constants qualified
(`MCP.MCP_RESOURCE_NOT_FOUND`).

Behavioral hooks (`validate_request`, `result_envelope`, `with_cache_hints`)
take arguments and are written as ordinary methods in the same file when a
revision customizes them.
"""
macro spec(spec, block)
    if !(spec isa Expr && spec.head === :call && length(spec.args) == 2 &&
         spec.args[1] === :Val)
        error("@spec: first argument must be `Val(:symbol)`")
    end
    tag = spec.args[2]
    if !(tag isa QuoteNode && tag.value isa Symbol)
        error("@spec: expected a literal symbol tag, e.g. Val(:v2025_06_18)")
    end

    declared = Symbol[]
    definitions = Any[]
    for statement in block.args
        statement isa LineNumberNode && continue
        if !(statement isa Expr && statement.head === :(=) && statement.args[1] isa Symbol)
            error("@spec: expected `capability = value` lines, got: $statement")
        end
        name, value = statement.args
        if !haskey(SPEC_TRAIT_TYPES, name)
            error("@spec: unknown capability `$name`; expected one of " *
                  join(string.(keys(SPEC_TRAIT_TYPES)), ", "))
        end
        if name in declared
            error("@spec: duplicate capability `$name`")
        end
        push!(declared, name)
        target = GlobalRef(SPEC_MODULE, name)
        type = SPEC_TRAIT_TYPES[name]
        push!(definitions, :($target(::Val{$(tag)})::$(type) = $(esc(value))))
    end

    omitted = [name for name in keys(SPEC_TRAIT_TYPES) if !(name in declared)]
    if !isempty(omitted)
        error("@spec: incomplete profile; missing " * join(string.(omitted), ", "))
    end

    return Expr(:block, definitions...)
end

# ----------------------------------------------------------------------------
# Neutral result-pipeline behaviors
# ----------------------------------------------------------------------------

# A revision overrides one of these only when it changes the result; the
# no-op/identity implementation is the correct neutral behavior, not a
# capability a revision must restate.
validate_request(::Val, ctx::ServerContext, req::Union{Nothing,HTTP.Request}, method::String, params) = nothing

result_envelope(::Val, ctx::ServerContext, result) = result

with_cache_hints(::Val, result; scope::String="public") = result

# ----------------------------------------------------------------------------
# Method surface (structural)
# ----------------------------------------------------------------------------

# Whether a revision serves a method at all. Shared methods exist in every
# revision; the six era-exclusive methods name their era once here rather than
# in every profile. The handler for an unavailable method is never reached:
# dispatch answers `-32601` first.
method_available(::Val, ::Val)::Bool = true
method_available(spec::Val, ::Val{:initialize})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:ping})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:resources_subscribe})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:resources_unsubscribe})::Bool = is_legacy(spec)
method_available(spec::Val, ::Val{:server_discover})::Bool = is_modern(spec)
method_available(spec::Val, ::Val{:subscriptions_listen})::Bool = is_modern(spec)
