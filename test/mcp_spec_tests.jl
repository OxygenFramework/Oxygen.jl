module MCPSpecTests

using Test
using HTTP
using Oxygen

const MCP = Oxygen.Core.MCP

const ALL_SPECS = (MCP.Specs.V2024_11_05, MCP.Specs.V2025_03_26, MCP.Specs.V2025_06_18,
                   MCP.Specs.V2025_11_25, MCP.Specs.V2026_07_28)

# A hypothetical future revision, declared exactly like a supported one. This
# is the extensibility proof: adding a revision is one `@spec` block, and the
# method surface is still structural.
const FAKE_SPEC = Val(:v2099_01_01)
MCP.@spec Val(:v2099_01_01) begin
    version_string           = "2099-01-01"
    spec_rank                = 6
    is_modern                = false
    uses_sessions            = true
    allows_batch             = false
    emits_structured_content = true
    shows_resource_icons     = true
    get_policy               = :legacy_sse
    delete_policy            = :session
    not_found_code           = MCP.MCP_RESOURCE_NOT_FOUND
end

# The capability keys every revision must state; a `@spec` block declares each
# as an interface method, so `hasmethod` proves nothing was left implicit.
const SPEC_TRAITS = (MCP.Specs.version_string, MCP.Specs.spec_rank, MCP.Specs.is_modern,
                     MCP.Specs.uses_sessions, MCP.Specs.allows_batch,
                     MCP.Specs.emits_structured_content, MCP.Specs.shows_resource_icons,
                     MCP.Specs.get_policy, MCP.Specs.delete_policy, MCP.Specs.not_found_code)

@testset "mcp every revision declares its full profile" begin
    for spec in ALL_SPECS, trait in SPEC_TRAITS
        @test hasmethod(trait, Tuple{typeof(spec)})
    end
end

# A complete, valid profile statement block. The malformed variants below are
# built by adding to / trimming this block, so each case differs from a valid
# profile in exactly one way.
const PROFILE_STATEMENTS = (
    :(version_string = "2099-01-02"),
    :(spec_rank = 6),
    :(is_modern = false),
    :(uses_sessions = true),
    :(allows_batch = false),
    :(emits_structured_content = true),
    :(shows_resource_icons = true),
    :(get_policy = :legacy_sse),
    :(delete_policy = :session),
    :(not_found_code = MCP.MCP_RESOURCE_NOT_FOUND),
)

# Build the `@spec Val(:v2099_01_02) begin <statements> end` macro call.
profile_expr(statements) = Expr(:macrocall, GlobalRef(MCP, Symbol("@spec")),
                                LineNumberNode(0), :(Val(:v2099_01_02)),
                                Expr(:block, statements...))

# Same, but with an arbitrary tag expression, for the tag-validation cases.
profile_expr(tag, statements) = Expr(:macrocall, GlobalRef(MCP, Symbol("@spec")),
                                     LineNumberNode(0), tag,
                                     Expr(:block, statements...))

# Malformed profiles are only expanded, never evaluated, so a rejected profile
# cannot leave partial method definitions behind on the spec module.
expand_profile(statements) = macroexpand(@__MODULE__, profile_expr(statements))

@testset "mcp @spec guards the revision profile contract" begin
    # A complete profile expands into one method definition per capability the
    # contract knows about, so a new revision only has to state its answers.
    expanded = expand_profile(PROFILE_STATEMENTS)
    @test expanded isa Expr
    for capability in keys(MCP.Specs.SPEC_TRAIT_TYPES)
        @test occursin(string(capability), string(expanded))
    end

    # A capability the macro does not know (`spec_rnk` for `spec_rank`) would
    # silently do nothing, so it is rejected instead.
    @test_throws ErrorException expand_profile((PROFILE_STATEMENTS..., :(spec_rnk = 6)))

    # Declaring a capability twice is ambiguous, so a repeated `spec_rank` is
    # rejected rather than letting the last line win.
    @test_throws ErrorException expand_profile((PROFILE_STATEMENTS..., :(spec_rank = 7)))

    # Skipping a capability leaves the revision without an implementation, so a
    # profile that stops before the final `not_found_code` line is rejected.
    @test_throws ErrorException expand_profile(PROFILE_STATEMENTS[1:(end - 1)])

    # ...and so is a block line that is not a capability declaration at all.
    @test_throws ErrorException expand_profile((PROFILE_STATEMENTS..., :(1 + 1)))

    # The revision tag must be a literal `Val(:symbol)`: a bare `Val`...
    @test_throws ErrorException macroexpand(@__MODULE__, profile_expr(:Val, PROFILE_STATEMENTS))
    # ...and a `Val` wrapping a string both fail to name a revision.
    @test_throws ErrorException macroexpand(@__MODULE__,
        profile_expr(:(Val("v2099_01_02")), PROFILE_STATEMENTS))
end

@testset "mcp spec identity: version strings, ranks, and lookup" begin
    @test [MCP.Specs.version_string(spec) for spec in ALL_SPECS] ==
        ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"]
    @test [MCP.Specs.spec_rank(spec) for spec in ALL_SPECS] == collect(1:5)

    # every advertised revision round-trips through the wire-string lookup, and
    # anything else is not a revision at all
    for spec in ALL_SPECS
        @test MCP.Specs.spec_from_version(MCP.Specs.version_string(spec)) === spec
    end
    @test MCP.Specs.spec_from_version("1999-01-01") === nothing
    @test MCP.Specs.spec_from_version("") === nothing
end

@testset "mcp advertised spec tuples" begin
    # MODERN_SPECS/LEGACY_SPECS group the revisions; the concatenation is the
    # advertised set and the LATEST_* constants are the negotiation fallbacks.
    @test MCP.Specs.MODERN_SPECS == (MCP.Specs.V2026_07_28,)
    @test MCP.Specs.LEGACY_SPECS == (MCP.Specs.V2025_11_25, MCP.Specs.V2025_06_18,
                               MCP.Specs.V2025_03_26, MCP.Specs.V2024_11_05)
    @test MCP.Specs.SUPPORTED_SPECS == (MCP.Specs.MODERN_SPECS..., MCP.Specs.LEGACY_SPECS...)
    @test MCP.Specs.LATEST_LEGACY_SPEC === MCP.Specs.V2025_11_25
    @test MCP.Specs.LATEST_MODERN_SPEC === MCP.Specs.V2026_07_28
end

@testset "mcp era classification" begin
    # exactly one era per revision: modern is 2026-07-28, everything else legacy
    @test MCP.Specs.is_modern(MCP.Specs.V2026_07_28)
    @test !MCP.Specs.is_legacy(MCP.Specs.V2026_07_28)
    for spec in MCP.Specs.LEGACY_SPECS
        @test !MCP.Specs.is_modern(spec)
        @test MCP.Specs.is_legacy(spec)
    end
end

@testset "mcp spec_at_least orders by revision rank" begin
    @test MCP.Specs.spec_at_least(MCP.Specs.V2025_06_18, MCP.Specs.V2025_03_26)
    @test MCP.Specs.spec_at_least(MCP.Specs.V2025_06_18, MCP.Specs.V2025_06_18)
    @test !MCP.Specs.spec_at_least(MCP.Specs.V2025_03_26, MCP.Specs.V2025_06_18)
    @test MCP.Specs.spec_at_least(MCP.Specs.V2026_07_28, MCP.Specs.V2025_11_25)
end

@testset "mcp revision capability profiles" begin
    ctx = Oxygen.Core.ServerContext()

    # The golden answers for each revision's capability questions, pinned per
    # revision; the conformance testsets below re-derive them from the era
    # predicates.

    # Batching existed only in 2025-03-26.
    @test MCP.Specs.allows_batch(MCP.Specs.V2025_03_26)
    for spec in (MCP.Specs.V2024_11_05, MCP.Specs.V2025_06_18, MCP.Specs.V2025_11_25, MCP.Specs.V2026_07_28)
        @test !MCP.Specs.allows_batch(spec)
    end

    # structuredContent and icons arrived in 2025-06-18.
    for spec in (MCP.Specs.V2025_06_18, MCP.Specs.V2025_11_25, MCP.Specs.V2026_07_28)
        @test MCP.Specs.emits_structured_content(spec)
        @test MCP.Specs.shows_resource_icons(spec)
    end
    for spec in (MCP.Specs.V2024_11_05, MCP.Specs.V2025_03_26)
        @test !MCP.Specs.emits_structured_content(spec)
        @test !MCP.Specs.shows_resource_icons(spec)
    end

    # Sessions exist only in the legacy era.
    @test all(MCP.Specs.uses_sessions, MCP.Specs.LEGACY_SPECS)
    @test !MCP.Specs.uses_sessions(MCP.Specs.V2026_07_28)

    # Transport policy: GET/DELETE are legacy concepts.
    @test MCP.Specs.get_policy(MCP.Specs.V2025_11_25) === :legacy_sse
    @test MCP.Specs.get_policy(MCP.Specs.V2026_07_28) === :reject
    @test MCP.Specs.delete_policy(MCP.Specs.V2025_11_25) === :session
    @test MCP.Specs.delete_policy(MCP.Specs.V2026_07_28) === :reject

    # Not-found code: -32002 legacy, -32602 modern.
    @test MCP.Specs.not_found_code(MCP.Specs.V2024_11_05) == MCP.MCP_RESOURCE_NOT_FOUND
    @test MCP.Specs.not_found_code(MCP.Specs.V2025_11_25) == MCP.MCP_RESOURCE_NOT_FOUND
    @test MCP.Specs.not_found_code(MCP.Specs.V2026_07_28) == MCP.MCP_INVALID_PARAMS

    # Validation and result shaping default to no-ops.
    @test MCP.Specs.validate_request(MCP.Specs.V2025_11_25, ctx, nothing,
                               "tools/list", Dict{String,Any}()) === nothing
    result = Dict{String,Any}("a" => 1)
    @test MCP.Specs.result_envelope(MCP.Specs.V2025_11_25, ctx, result) === result
    @test MCP.Specs.with_cache_hints(MCP.Specs.V2025_11_25, result) === result
end

@testset "mcp method routing" begin
    # Every wire name maps to exactly one implementation tag.
    for (wire, tag) in (
        "initialize" => Val(:initialize),
        "server/discover" => Val(:server_discover),
        "ping" => Val(:ping),
        "tools/list" => Val(:tools_list),
        "tools/call" => Val(:tools_call),
        "prompts/list" => Val(:prompts_list),
        "prompts/get" => Val(:prompts_get),
        "resources/list" => Val(:resources_list),
        "resources/templates/list" => Val(:resources_templates_list),
        "resources/read" => Val(:resources_read),
        "resources/subscribe" => Val(:resources_subscribe),
        "resources/unsubscribe" => Val(:resources_unsubscribe),
        "subscriptions/listen" => Val(:subscriptions_listen),
    )
        @test MCP.Dispatch.method_val(wire) === tag
    end
    @test MCP.Dispatch.method_val("no/such/method") === Val(:unknown)

    ctx = Oxygen.Core.ServerContext()

    # Unknown methods and unknown tags fall back to -32601, never a handler.
    body, status = MCP.Dispatch.dispatch(ctx, nothing, 1, "no/such",
                                Dict{String,Any}(); spec=MCP.Specs.LATEST_LEGACY_SPEC)
    @test status == 404
    @test body["error"]["code"] == MCP.Errors.MCP_METHOD_NOT_FOUND

    # Era-exclusive methods are gated by `method_available` before routing:
    # modern `initialize` and legacy `server/discover` are both unknown there.
    body, status = MCP.Dispatch.dispatch(ctx, nothing, 1, "initialize",
                                Dict{String,Any}(); spec=MCP.Specs.V2026_07_28)
    @test status == 404
    @test body["error"]["code"] == MCP.Errors.MCP_METHOD_NOT_FOUND
    body, status = MCP.Dispatch.dispatch(ctx, nothing, 1, "server/discover",
                                Dict{String,Any}(); spec=MCP.Specs.LATEST_LEGACY_SPEC)
    @test status == 404
    @test body["error"]["code"] == MCP.Errors.MCP_METHOD_NOT_FOUND

    # A revision with no per-method code inherits every shared implementation.
    body, status = MCP.Dispatch.dispatch(ctx, nothing, 1, "tools/list",
                                Dict{String,Any}(); spec=FAKE_SPEC)
    @test status == 200
    @test isempty(body["result"]["tools"])
end

@testset "mcp modern overrides" begin
    ctx = Oxygen.Core.ServerContext()

    # The modern contract rejects a request without `_meta.protocolVersion`.
    @test_throws MCP.MCPRequestError MCP.Specs.validate_request(
        MCP.Specs.V2026_07_28, ctx, nothing, "tools/list", Dict{String,Any}())

    enveloped = MCP.Specs.result_envelope(MCP.Specs.V2026_07_28, ctx,
                                    Dict{String,Any}("a" => 1))
    @test enveloped["resultType"] == "complete"
    @test enveloped[MCP.Envelopes.META_KEY][MCP.Envelopes.META_SERVER_INFO]["name"] == "Oxygen"

    hinted = MCP.Specs.with_cache_hints(MCP.Specs.V2026_07_28, Dict{String,Any}(); scope="private")
    @test hinted["ttlMs"] == MCP.Envelopes.LIST_TTL_MS
    @test hinted["cacheScope"] == "private"
end

@testset "mcp derived version constants" begin
    @test MCP.Specs.MODERN_VERSIONS == ["2026-07-28"]
    @test MCP.Specs.LATEST_MODERN_VERSION == "2026-07-28"
    @test MCP.Specs.PROTOCOL_VERSION == "2026-07-28"
    @test MCP.Specs.LEGACY_VERSIONS == ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    @test MCP.Specs.LATEST_LEGACY == "2025-11-25"
    @test MCP.Specs.SUPPORTED_VERSIONS == ["2026-07-28", "2025-11-25", "2025-06-18",
                                     "2025-03-26", "2024-11-05"]
end

@testset "mcp wire version parsing" begin
    # structuredContent and resource icons track the 2025-06-18 threshold for
    # every advertised revision
    for version in ("2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28")
        spec = MCP.Specs.spec_from_version(version)
        @test MCP.Specs.emits_structured_content(spec) == MCP.Specs.spec_at_least(spec, MCP.Specs.V2025_06_18)
        @test MCP.Specs.shows_resource_icons(spec) == MCP.Specs.spec_at_least(spec, MCP.Specs.V2025_06_18)
    end
    # an unknown version falls back to the latest legacy revision, matching
    # negotiation's fallback
    @test MCP.Specs.spec_or_latest_legacy("1900-01-01") === MCP.Specs.LATEST_LEGACY_SPEC
end

@testset "mcp request spec resolution" begin
    ctx = Oxygen.Core.ServerContext()

    # No modern claim: the session's negotiated wire version decides.
    @test MCP.Dispatch.request_spec(ctx, nothing, "tools/list", Dict{String,Any}()) === MCP.Specs.LATEST_LEGACY_SPEC
    ctx.mcp.session_version[] = "2025-03-26"
    @test MCP.Dispatch.request_spec(ctx, nothing, "tools/list", Dict{String,Any}()) === MCP.Specs.V2025_03_26
    # an unknown negotiated version falls back to the latest legacy revision
    ctx.mcp.session_version[] = "1900-01-01"
    @test MCP.Dispatch.request_spec(ctx, nothing, "tools/list", Dict{String,Any}()) === MCP.Specs.LATEST_LEGACY_SPEC

    # A modern `_meta` version names its own revision; an unsupported or legacy
    # claim is `nothing` (the caller answers -32022).
    meta_for(version) = Dict{String,Any}(
        "_meta" => Dict{String,Any}(MCP.Envelopes.META_PROTOCOL => version))
    @test MCP.Dispatch.request_spec(ctx, nothing, "tools/list", meta_for("2026-07-28")) === MCP.Specs.V2026_07_28
    @test MCP.Dispatch.request_spec(ctx, nothing, "tools/list", meta_for("1900-01-01")) === nothing
    @test MCP.Dispatch.request_spec(ctx, nothing, "tools/list", meta_for("2025-03-26")) === nothing

    # `server/discover` claims modern by itself.
    @test MCP.Dispatch.request_spec(ctx, nothing, "server/discover", Dict{String,Any}()) === MCP.Specs.V2026_07_28

    # Over HTTP a modern `MCP-Protocol-Version` header claims modern too.
    modern_req = HTTP.Request("POST", "/mcp", ["MCP-Protocol-Version" => "2026-07-28"])
    @test MCP.Dispatch.request_spec(ctx, modern_req, "tools/list", Dict{String,Any}()) === MCP.Specs.V2026_07_28
    # A legacy header version only marks the request legacy; the negotiated
    # version still decides (here the unknown one fell back above).
    legacy_req = HTTP.Request("POST", "/mcp", ["MCP-Protocol-Version" => "2025-03-26"])
    @test MCP.Dispatch.request_spec(ctx, legacy_req, "tools/list", Dict{String,Any}()) === MCP.Specs.LATEST_LEGACY_SPEC
end

@testset "mcp transport policy spec" begin
    ctx = Oxygen.Core.ServerContext()
    plain_req = HTTP.Request("GET", "/mcp")
    modern_req = HTTP.Request("GET", "/mcp", ["MCP-Protocol-Version" => "2026-07-28"])

    # A body-less request has no `_meta`: the version header alone names the
    # revision, anything else falls back to the context's legacy revision.
    @test MCP.Dispatch.transport_spec(ctx, modern_req) === MCP.Specs.V2026_07_28
    @test MCP.Dispatch.transport_spec(ctx, plain_req) === MCP.Specs.LATEST_LEGACY_SPEC

    # The policy interface answers the GET/DELETE/session questions, so the
    # transports never compare version strings themselves.
    @test MCP.Specs.get_policy(MCP.Dispatch.transport_spec(ctx, modern_req)) === :reject
    @test MCP.Specs.delete_policy(MCP.Dispatch.transport_spec(ctx, modern_req)) === :reject
    @test MCP.Specs.get_policy(MCP.Dispatch.transport_spec(ctx, plain_req)) === :legacy_sse
    @test MCP.Specs.delete_policy(MCP.Dispatch.transport_spec(ctx, plain_req)) === :session
    @test MCP.Specs.uses_sessions(MCP.Dispatch.transport_spec(ctx, plain_req))
    @test !MCP.Specs.uses_sessions(MCP.Dispatch.transport_spec(ctx, modern_req))

    # A modern claim in `_meta` (even an unsupported one, which `process`
    # answers with -32022) classifies as stateless, so no session is resolved
    # for it; `server/discover` claims modern by itself.
    params_for(version) = Dict{String,Any}(MCP.Envelopes.META_KEY =>
        Dict{String,Any}(MCP.Envelopes.META_PROTOCOL => version))
    modern_payload = Dict{String,Any}("method" => "tools/list", "params" => params_for("2026-07-28"))
    @test MCP.Dispatch.transport_spec(ctx, plain_req, modern_payload) === MCP.Specs.V2026_07_28
    unsupported_payload = Dict{String,Any}("method" => "tools/list", "params" => params_for("1900-01-01"))
    @test MCP.Dispatch.transport_spec(ctx, plain_req, unsupported_payload) === MCP.Specs.LATEST_MODERN_SPEC
    @test MCP.Dispatch.request_spec(ctx, plain_req, "tools/list", params_for("1900-01-01")) === nothing
    discover_payload = Dict{String,Any}("method" => "server/discover", "params" => Dict{String,Any}())
    @test MCP.Dispatch.transport_spec(ctx, plain_req, discover_payload) === MCP.Specs.LATEST_MODERN_SPEC
end

# The full method surface, by tag: shared methods are served by every revision,
# the six era-exclusive methods only by their own era. This is the table form
# of the surface — the per-revision answers live in the capability profiles
# above; this testset cross-checks them against the era predicates, so a
# profile cannot drift from its declared era.
const SHARED_METHOD_TAGS = (:tools_list, :tools_call, :prompts_list, :prompts_get,
                            :resources_list, :resources_templates_list, :resources_read)
const LEGACY_ONLY_METHOD_TAGS = (:initialize, :ping, :resources_subscribe,
                                 :resources_unsubscribe)
const MODERN_ONLY_METHOD_TAGS = (:server_discover, :subscriptions_listen)

@testset "mcp conformance: method surface table" begin
    for spec in ALL_SPECS
        for tag in SHARED_METHOD_TAGS
            @test MCP.Specs.method_available(spec, Val(tag))
        end
        for tag in LEGACY_ONLY_METHOD_TAGS
            @test MCP.Specs.method_available(spec, Val(tag)) == MCP.Specs.is_legacy(spec)
        end
        for tag in MODERN_ONLY_METHOD_TAGS
            @test MCP.Specs.method_available(spec, Val(tag)) == MCP.Specs.is_modern(spec)
        end
        # Unknown tags pass the availability gate and fall to the -32601 handler.
        @test MCP.Specs.method_available(spec, Val(:unknown))
    end
end

@testset "mcp conformance: transport policy table" begin
    # The policy answers must follow the era predicates for every revision:
    # sessions and the legacy GET/DELETE policies belong to the legacy era,
    # modern revisions reject both.
    for spec in ALL_SPECS
        modern = MCP.Specs.is_modern(spec)
        @test MCP.Specs.uses_sessions(spec) == !modern
        @test (MCP.Specs.get_policy(spec) === :reject) == modern
        @test (MCP.Specs.delete_policy(spec) === :reject) == modern
    end

    # Legacy result shaping defaults to identity for every legacy revision.
    ctx = Oxygen.Core.ServerContext()
    for spec in MCP.Specs.LEGACY_SPECS
        @test MCP.Specs.validate_request(spec, ctx, nothing, "tools/list", Dict{String,Any}()) === nothing
        result = Dict{String,Any}("x" => 1)
        @test MCP.Specs.result_envelope(spec, ctx, result) === result
        @test MCP.Specs.with_cache_hints(spec, result) === result
        @test MCP.Specs.not_found_code(spec) == MCP.MCP_RESOURCE_NOT_FOUND
    end
end

@testset "mcp conformance: era gating rejects at dispatch" begin
    ctx = Oxygen.Core.ServerContext()
    exclusive = (
        ("initialize", :legacy),
        ("ping", :legacy),
        ("resources/subscribe", :legacy),
        ("resources/unsubscribe", :legacy),
        ("server/discover", :modern),
        ("subscriptions/listen", :modern),
    )

    # An era-exclusive method is only served by a spec of that era; the other
    # era answers -32601 before reaching any handler.
    for spec in ALL_SPECS
        for (wire, method_era) in exclusive
            served = (method_era === :modern) == MCP.Specs.is_modern(spec)
            body, status = MCP.Dispatch.dispatch(ctx, nothing, 1, wire, Dict{String,Any}(); spec=spec)
            if served
                # Served here: the handler ran (it may reject bad params, but
                # never as an unknown method).
                @test status in (200, 400)
                @test get(get(body, "error", Dict{String,Any}()), "code", nothing) !=
                    MCP.Errors.MCP_METHOD_NOT_FOUND
            else
                @test status == 404
                @test body["error"]["code"] == MCP.Errors.MCP_METHOD_NOT_FOUND
            end
        end
    end
end

@testset "mcp negotiation" begin
    for version in ("2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25")
        @test MCP.Specs.negotiate_version(version) == version
    end
    # a modern version cannot be negotiated on the legacy handshake
    @test MCP.Specs.negotiate_version("2026-07-28") == "2025-11-25"
    @test MCP.Specs.negotiate_version("1900-01-01") == "2025-11-25"
    @test MCP.Specs.negotiate_version(nothing) == "2025-11-25"
end

@testset "mcp result shaping via strategies" begin
    ctx = Oxygen.Core.ServerContext()

    modern_list = MCP.Serialization.list_result("tools", Dict{String,Any}[]; spec=MCP.Specs.V2026_07_28)
    @test modern_list["ttlMs"] == 0
    @test modern_list["cacheScope"] == "public"
    legacy_list = MCP.Serialization.list_result("tools", Dict{String,Any}[]; spec=MCP.Specs.V2025_11_25)
    @test !haskey(legacy_list, "ttlMs")
    @test !haskey(legacy_list, "cacheScope")

    modern_body, status = MCP.Serialization.result_response(ctx, 1, Dict{String,Any}("x" => 1);
                                              spec=MCP.Specs.V2026_07_28)
    @test status == 200
    @test modern_body["result"]["resultType"] == "complete"
    legacy_body, _ = MCP.Serialization.result_response(ctx, 1, Dict{String,Any}("x" => 1);
                                         spec=MCP.Specs.V2025_11_25)
    @test !haskey(legacy_body["result"], "resultType")
end

@testset "mcp new revision profile" begin
    @test MCP.Specs.version_string(FAKE_SPEC) == "2099-01-01"
    @test MCP.Specs.spec_rank(FAKE_SPEC) == 6

    # The fake revision states its own complete profile; the method surface is
    # still inherited structurally from the era predicates.
    @test MCP.Specs.is_legacy(FAKE_SPEC)
    @test !MCP.Specs.is_modern(FAKE_SPEC)
    @test MCP.Specs.uses_sessions(FAKE_SPEC)
    @test MCP.Specs.get_policy(FAKE_SPEC) === :legacy_sse
    @test MCP.Specs.delete_policy(FAKE_SPEC) === :session
    @test !MCP.Specs.allows_batch(FAKE_SPEC)
    @test MCP.Specs.emits_structured_content(FAKE_SPEC)
    @test MCP.Specs.shows_resource_icons(FAKE_SPEC)
    @test MCP.Specs.not_found_code(FAKE_SPEC) == MCP.MCP_RESOURCE_NOT_FOUND
    for tag in SHARED_METHOD_TAGS
        @test MCP.Specs.method_available(FAKE_SPEC, Val(tag))
    end
    for tag in LEGACY_ONLY_METHOD_TAGS
        @test MCP.Specs.method_available(FAKE_SPEC, Val(tag))
    end
    for tag in MODERN_ONLY_METHOD_TAGS
        @test !MCP.Specs.method_available(FAKE_SPEC, Val(tag))
    end

    # Unknown methods still yield -32601 under a new revision.
    body, status = MCP.Dispatch.dispatch(Oxygen.Core.ServerContext(), nothing, 1, "no/such",
                                Dict{String,Any}(); spec=FAKE_SPEC)
    @test status == 404
    @test body["error"]["code"] == MCP.Errors.MCP_METHOD_NOT_FOUND
end

@testset "mcp submodule extension points" begin
    # The generic lives in Dispatch and each domain extends it explicitly.
    @test parentmodule(MCP.Dispatch.handle_method) === MCP.Dispatch
    @test MCP.Dispatch.handle_method === MCP.Dispatch.handle_method
    owners = Set(method.module for method in methods(MCP.Dispatch.handle_method))
    @test owners == Set([MCP.Dispatch, MCP.Discovery, MCP.Tools, MCP.Prompts,
                         MCP.Resources, MCP.Subscriptions])
    @test length(methods(MCP.Dispatch.handle_method)) == 14

    # The @spec macro targets the Specs module, and every revision is a method.
    @test MCP.Specs.SPEC_MODULE === MCP.Specs
    for spec in ALL_SPECS
        @test hasmethod(MCP.Specs.version_string, Tuple{typeof(spec)})
    end

    # Streaming stays an explicit extension of the Streaming generics.
    @test any(method.module === MCP.Streams for method in methods(MCP.emit))
    @test any(method.module === MCP.Streams for method in methods(MCP.normalize_event))
end

end
