module MCPSpecTests

using Test
using HTTP
using Oxygen

const MCP = Oxygen.Core.MCP

const ALL_SPECS = (MCP.V2024_11_05, MCP.V2025_03_26, MCP.V2025_06_18,
                   MCP.V2025_11_25, MCP.V2026_07_28)

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
const SPEC_TRAITS = (MCP.version_string, MCP.spec_rank, MCP.is_modern,
                     MCP.uses_sessions, MCP.allows_batch,
                     MCP.emits_structured_content, MCP.shows_resource_icons,
                     MCP.get_policy, MCP.delete_policy, MCP.not_found_code)

@testset "mcp every revision declares its full profile" begin
    for spec in ALL_SPECS, trait in SPEC_TRAITS
        @test hasmethod(trait, Tuple{typeof(spec)})
    end
end

# A profile that passes `@spec` validation. Malformed variants are expanded
# (never evaluated), proving the macro rejects them without defining methods.
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

profile_expr(statements) = Expr(:macrocall, GlobalRef(MCP, Symbol("@spec")),
                                LineNumberNode(0), :(Val(:v2099_01_02)),
                                Expr(:block, statements...))

@testset "mcp @spec validates the profile contract" begin
    @test macroexpand(@__MODULE__, profile_expr(PROFILE_STATEMENTS)) isa Expr
    @test_throws ErrorException macroexpand(@__MODULE__,
        profile_expr((PROFILE_STATEMENTS..., :(spec_rnk = 6))))
    @test_throws ErrorException macroexpand(@__MODULE__,
        profile_expr((PROFILE_STATEMENTS..., :(spec_rank = 7))))
    @test_throws ErrorException macroexpand(@__MODULE__,
        profile_expr(PROFILE_STATEMENTS[1:(end - 1)]))
end

@testset "mcp spec identity" begin
    @test [MCP.version_string(spec) for spec in ALL_SPECS] ==
        ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"]
    @test [MCP.spec_rank(spec) for spec in ALL_SPECS] == collect(1:5)

    for spec in ALL_SPECS
        @test MCP.spec_from_version(MCP.version_string(spec)) === spec
    end
    @test MCP.spec_from_version("1999-01-01") === nothing
    @test MCP.spec_from_version("") === nothing
end

@testset "mcp advertised spec tuples" begin
    @test MCP.MODERN_SPECS == (MCP.V2026_07_28,)
    @test MCP.LEGACY_SPECS == (MCP.V2025_11_25, MCP.V2025_06_18,
                               MCP.V2025_03_26, MCP.V2024_11_05)
    @test MCP.SUPPORTED_SPECS == (MCP.MODERN_SPECS..., MCP.LEGACY_SPECS...)
    @test MCP.LATEST_LEGACY_SPEC === MCP.V2025_11_25
    @test MCP.LATEST_MODERN_SPEC === MCP.V2026_07_28
end

@testset "mcp era classification" begin
    @test MCP.is_modern(MCP.V2026_07_28)
    @test !MCP.is_legacy(MCP.V2026_07_28)
    for spec in MCP.LEGACY_SPECS
        @test !MCP.is_modern(spec)
        @test MCP.is_legacy(spec)
    end
end

@testset "mcp spec ordering" begin
    @test MCP.spec_at_least(MCP.V2025_06_18, MCP.V2025_03_26)
    @test MCP.spec_at_least(MCP.V2025_06_18, MCP.V2025_06_18)
    @test !MCP.spec_at_least(MCP.V2025_03_26, MCP.V2025_06_18)
    @test MCP.spec_at_least(MCP.V2026_07_28, MCP.V2025_11_25)
end

@testset "mcp capability profiles" begin
    ctx = Oxygen.Core.ServerContext()

    # Batching existed only in 2025-03-26.
    @test MCP.allows_batch(MCP.V2025_03_26)
    for spec in (MCP.V2024_11_05, MCP.V2025_06_18, MCP.V2025_11_25, MCP.V2026_07_28)
        @test !MCP.allows_batch(spec)
    end

    # structuredContent and icons arrived in 2025-06-18.
    for spec in (MCP.V2025_06_18, MCP.V2025_11_25, MCP.V2026_07_28)
        @test MCP.emits_structured_content(spec)
        @test MCP.shows_resource_icons(spec)
    end
    for spec in (MCP.V2024_11_05, MCP.V2025_03_26)
        @test !MCP.emits_structured_content(spec)
        @test !MCP.shows_resource_icons(spec)
    end

    # Sessions exist only in the legacy era.
    @test all(MCP.uses_sessions, MCP.LEGACY_SPECS)
    @test !MCP.uses_sessions(MCP.V2026_07_28)

    # Transport policy: GET/DELETE are legacy concepts.
    @test MCP.get_policy(MCP.V2025_11_25) === :legacy_sse
    @test MCP.get_policy(MCP.V2026_07_28) === :reject
    @test MCP.delete_policy(MCP.V2025_11_25) === :session
    @test MCP.delete_policy(MCP.V2026_07_28) === :reject

    # Not-found code: -32002 legacy, -32602 modern.
    @test MCP.not_found_code(MCP.V2024_11_05) == MCP.MCP_RESOURCE_NOT_FOUND
    @test MCP.not_found_code(MCP.V2025_11_25) == MCP.MCP_RESOURCE_NOT_FOUND
    @test MCP.not_found_code(MCP.V2026_07_28) == MCP.MCP_INVALID_PARAMS

    # Validation and result shaping default to no-ops.
    @test MCP.validate_request(MCP.V2025_11_25, ctx, nothing,
                               "tools/list", Dict{String,Any}()) === nothing
    result = Dict{String,Any}("a" => 1)
    @test MCP.result_envelope(MCP.V2025_11_25, ctx, result) === result
    @test MCP.with_cache_hints(MCP.V2025_11_25, result) === result
end

@testset "mcp method availability" begin
    for spec in ALL_SPECS
        @test MCP.method_available(spec, Val(:tools_list))
        @test MCP.method_available(spec, Val(:tools_call))
        @test MCP.method_available(spec, Val(:prompts_list))
        @test MCP.method_available(spec, Val(:resources_read))
    end

    for spec in MCP.LEGACY_SPECS
        @test MCP.method_available(spec, Val(:initialize))
        @test MCP.method_available(spec, Val(:ping))
        @test MCP.method_available(spec, Val(:resources_subscribe))
        @test MCP.method_available(spec, Val(:resources_unsubscribe))
        @test !MCP.method_available(spec, Val(:server_discover))
        @test !MCP.method_available(spec, Val(:subscriptions_listen))
    end

    @test !MCP.method_available(MCP.V2026_07_28, Val(:initialize))
    @test !MCP.method_available(MCP.V2026_07_28, Val(:ping))
    @test !MCP.method_available(MCP.V2026_07_28, Val(:resources_subscribe))
    @test !MCP.method_available(MCP.V2026_07_28, Val(:resources_unsubscribe))
    @test MCP.method_available(MCP.V2026_07_28, Val(:server_discover))
    @test MCP.method_available(MCP.V2026_07_28, Val(:subscriptions_listen))
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
        @test MCP.method_val(wire) === tag
    end
    @test MCP.method_val("no/such/method") === Val(:unknown)

    ctx = Oxygen.Core.ServerContext()

    # Unknown methods and unknown tags fall back to -32601, never a handler.
    body, status = MCP.dispatch(ctx, nothing, 1, "no/such",
                                Dict{String,Any}(); spec=MCP.LATEST_LEGACY_SPEC)
    @test status == 404
    @test body["error"]["code"] == MCP.MCP_METHOD_NOT_FOUND

    # Era-exclusive methods are gated by `method_available` before routing:
    # modern `initialize` and legacy `server/discover` are both unknown there.
    body, status = MCP.dispatch(ctx, nothing, 1, "initialize",
                                Dict{String,Any}(); spec=MCP.V2026_07_28)
    @test status == 404
    @test body["error"]["code"] == MCP.MCP_METHOD_NOT_FOUND
    body, status = MCP.dispatch(ctx, nothing, 1, "server/discover",
                                Dict{String,Any}(); spec=MCP.LATEST_LEGACY_SPEC)
    @test status == 404
    @test body["error"]["code"] == MCP.MCP_METHOD_NOT_FOUND

    # A revision with no per-method code inherits every shared implementation.
    body, status = MCP.dispatch(ctx, nothing, 1, "tools/list",
                                Dict{String,Any}(); spec=FAKE_SPEC)
    @test status == 200
    @test isempty(body["result"]["tools"])
end

@testset "mcp modern overrides" begin
    ctx = Oxygen.Core.ServerContext()

    # The modern contract rejects a request without `_meta.protocolVersion`.
    @test_throws MCP.MCPRequestError MCP.validate_request(
        MCP.V2026_07_28, ctx, nothing, "tools/list", Dict{String,Any}())

    enveloped = MCP.result_envelope(MCP.V2026_07_28, ctx,
                                    Dict{String,Any}("a" => 1))
    @test enveloped["resultType"] == "complete"
    @test enveloped[MCP.META_KEY][MCP.META_SERVER_INFO]["name"] == "Oxygen"

    hinted = MCP.with_cache_hints(MCP.V2026_07_28, Dict{String,Any}(); scope="private")
    @test hinted["ttlMs"] == MCP.LIST_TTL_MS
    @test hinted["cacheScope"] == "private"
end

@testset "mcp derived version constants" begin
    @test MCP.MODERN_VERSIONS == ["2026-07-28"]
    @test MCP.LATEST_MODERN_VERSION == "2026-07-28"
    @test MCP.PROTOCOL_VERSION == "2026-07-28"
    @test MCP.LEGACY_VERSIONS == ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    @test MCP.LATEST_LEGACY == "2025-11-25"
    @test MCP.SUPPORTED_VERSIONS == ["2026-07-28", "2025-11-25", "2025-06-18",
                                     "2025-03-26", "2024-11-05"]
end

@testset "mcp wire version parsing" begin
    for version in ("2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28")
        spec = MCP.spec_from_version(version)
        @test MCP.emits_structured_content(spec) == MCP.spec_at_least(spec, MCP.V2025_06_18)
        @test MCP.shows_resource_icons(spec) == MCP.spec_at_least(spec, MCP.V2025_06_18)
    end
    # an unknown version falls back to the latest legacy revision, matching
    # negotiation's fallback
    @test MCP.spec_or_latest_legacy("1900-01-01") === MCP.LATEST_LEGACY_SPEC
end

@testset "mcp request spec resolution" begin
    ctx = Oxygen.Core.ServerContext()

    # No modern claim: the session's negotiated wire version decides.
    @test MCP.request_spec(ctx, nothing, "tools/list", Dict{String,Any}()) === MCP.LATEST_LEGACY_SPEC
    ctx.mcp.session_version[] = "2025-03-26"
    @test MCP.request_spec(ctx, nothing, "tools/list", Dict{String,Any}()) === MCP.V2025_03_26
    # an unknown negotiated version falls back to the latest legacy revision
    ctx.mcp.session_version[] = "1900-01-01"
    @test MCP.request_spec(ctx, nothing, "tools/list", Dict{String,Any}()) === MCP.LATEST_LEGACY_SPEC

    # A modern `_meta` version names its own revision; an unsupported or legacy
    # claim is `nothing` (the caller answers -32022).
    meta_for(version) = Dict{String,Any}(
        "_meta" => Dict{String,Any}(MCP.META_PROTOCOL => version))
    @test MCP.request_spec(ctx, nothing, "tools/list", meta_for("2026-07-28")) === MCP.V2026_07_28
    @test MCP.request_spec(ctx, nothing, "tools/list", meta_for("1900-01-01")) === nothing
    @test MCP.request_spec(ctx, nothing, "tools/list", meta_for("2025-03-26")) === nothing

    # `server/discover` claims modern by itself.
    @test MCP.request_spec(ctx, nothing, "server/discover", Dict{String,Any}()) === MCP.V2026_07_28

    # Over HTTP a modern `MCP-Protocol-Version` header claims modern too.
    modern_req = HTTP.Request("POST", "/mcp", ["MCP-Protocol-Version" => "2026-07-28"])
    @test MCP.request_spec(ctx, modern_req, "tools/list", Dict{String,Any}()) === MCP.V2026_07_28
    # A legacy header version only marks the request legacy; the negotiated
    # version still decides (here the unknown one fell back above).
    legacy_req = HTTP.Request("POST", "/mcp", ["MCP-Protocol-Version" => "2025-03-26"])
    @test MCP.request_spec(ctx, legacy_req, "tools/list", Dict{String,Any}()) === MCP.LATEST_LEGACY_SPEC
end

@testset "mcp transport policy spec" begin
    ctx = Oxygen.Core.ServerContext()
    plain_req = HTTP.Request("GET", "/mcp")
    modern_req = HTTP.Request("GET", "/mcp", ["MCP-Protocol-Version" => "2026-07-28"])

    # A body-less request has no `_meta`: the version header alone names the
    # revision, anything else falls back to the context's legacy revision.
    @test MCP.transport_spec(ctx, modern_req) === MCP.V2026_07_28
    @test MCP.transport_spec(ctx, plain_req) === MCP.LATEST_LEGACY_SPEC

    # The policy interface answers the GET/DELETE/session questions, so the
    # transports never compare version strings themselves.
    @test MCP.get_policy(MCP.transport_spec(ctx, modern_req)) === :reject
    @test MCP.delete_policy(MCP.transport_spec(ctx, modern_req)) === :reject
    @test MCP.get_policy(MCP.transport_spec(ctx, plain_req)) === :legacy_sse
    @test MCP.delete_policy(MCP.transport_spec(ctx, plain_req)) === :session
    @test MCP.uses_sessions(MCP.transport_spec(ctx, plain_req))
    @test !MCP.uses_sessions(MCP.transport_spec(ctx, modern_req))

    # A modern claim in `_meta` (even an unsupported one, which `process`
    # answers with -32022) classifies as stateless, so no session is resolved
    # for it; `server/discover` claims modern by itself.
    params_for(version) = Dict{String,Any}(MCP.META_KEY =>
        Dict{String,Any}(MCP.META_PROTOCOL => version))
    modern_payload = Dict{String,Any}("method" => "tools/list", "params" => params_for("2026-07-28"))
    @test MCP.transport_spec(ctx, plain_req, modern_payload) === MCP.V2026_07_28
    unsupported_payload = Dict{String,Any}("method" => "tools/list", "params" => params_for("1900-01-01"))
    @test MCP.transport_spec(ctx, plain_req, unsupported_payload) === MCP.LATEST_MODERN_SPEC
    @test MCP.request_spec(ctx, plain_req, "tools/list", params_for("1900-01-01")) === nothing
    discover_payload = Dict{String,Any}("method" => "server/discover", "params" => Dict{String,Any}())
    @test MCP.transport_spec(ctx, plain_req, discover_payload) === MCP.LATEST_MODERN_SPEC
end

# The full method surface, by tag: shared methods are served by every revision,
# the six era-exclusive methods only by their own era.
const SHARED_METHOD_TAGS = (:tools_list, :tools_call, :prompts_list, :prompts_get,
                            :resources_list, :resources_templates_list, :resources_read)
const LEGACY_ONLY_METHOD_TAGS = (:initialize, :ping, :resources_subscribe,
                                 :resources_unsubscribe)
const MODERN_ONLY_METHOD_TAGS = (:server_discover, :subscriptions_listen)

@testset "mcp conformance: method surface table" begin
    for spec in ALL_SPECS
        for tag in SHARED_METHOD_TAGS
            @test MCP.method_available(spec, Val(tag))
        end
        for tag in LEGACY_ONLY_METHOD_TAGS
            @test MCP.method_available(spec, Val(tag)) == MCP.is_legacy(spec)
        end
        for tag in MODERN_ONLY_METHOD_TAGS
            @test MCP.method_available(spec, Val(tag)) == MCP.is_modern(spec)
        end
        # Unknown tags pass the availability gate and fall to the -32601 handler.
        @test MCP.method_available(spec, Val(:unknown))
    end
end

@testset "mcp conformance: transport policy table" begin
    for spec in ALL_SPECS
        modern = MCP.is_modern(spec)
        @test MCP.uses_sessions(spec) == !modern
        @test (MCP.get_policy(spec) === :reject) == modern
        @test (MCP.delete_policy(spec) === :reject) == modern
    end

    # Legacy result shaping defaults to identity for every legacy revision.
    ctx = Oxygen.Core.ServerContext()
    for spec in MCP.LEGACY_SPECS
        @test MCP.validate_request(spec, ctx, nothing, "tools/list", Dict{String,Any}()) === nothing
        result = Dict{String,Any}("x" => 1)
        @test MCP.result_envelope(spec, ctx, result) === result
        @test MCP.with_cache_hints(spec, result) === result
        @test MCP.not_found_code(spec) == MCP.MCP_RESOURCE_NOT_FOUND
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

    for spec in ALL_SPECS
        for (wire, era) in exclusive
            body, status = MCP.dispatch(ctx, nothing, 1, wire, Dict{String,Any}(); spec=spec)
            if (era === :modern) == MCP.is_modern(spec)
                # Served here: the handler ran (it may reject bad params, but
                # never as an unknown method).
                @test status in (200, 400)
                @test get(get(body, "error", Dict{String,Any}()), "code", nothing) !=
                    MCP.MCP_METHOD_NOT_FOUND
            else
                @test status == 404
                @test body["error"]["code"] == MCP.MCP_METHOD_NOT_FOUND
            end
        end
    end
end

@testset "mcp negotiation" begin
    for version in ("2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25")
        @test MCP.negotiate_version(version) == version
    end
    # a modern version cannot be negotiated on the legacy handshake
    @test MCP.negotiate_version("2026-07-28") == "2025-11-25"
    @test MCP.negotiate_version("1900-01-01") == "2025-11-25"
    @test MCP.negotiate_version(nothing) == "2025-11-25"
end

@testset "mcp result shaping via strategies" begin
    ctx = Oxygen.Core.ServerContext()

    modern_list = MCP.list_result("tools", Dict{String,Any}[]; spec=MCP.V2026_07_28)
    @test modern_list["ttlMs"] == 0
    @test modern_list["cacheScope"] == "public"
    legacy_list = MCP.list_result("tools", Dict{String,Any}[]; spec=MCP.V2025_11_25)
    @test !haskey(legacy_list, "ttlMs")
    @test !haskey(legacy_list, "cacheScope")

    modern_body, status = MCP.result_response(ctx, 1, Dict{String,Any}("x" => 1);
                                              spec=MCP.V2026_07_28)
    @test status == 200
    @test modern_body["result"]["resultType"] == "complete"
    legacy_body, _ = MCP.result_response(ctx, 1, Dict{String,Any}("x" => 1);
                                         spec=MCP.V2025_11_25)
    @test !haskey(legacy_body["result"], "resultType")
end

@testset "mcp new revision profile" begin
    @test MCP.version_string(FAKE_SPEC) == "2099-01-01"
    @test MCP.spec_rank(FAKE_SPEC) == 6

    # The fake revision states its own complete profile; the method surface is
    # still inherited structurally from the era predicates.
    @test MCP.is_legacy(FAKE_SPEC)
    @test !MCP.is_modern(FAKE_SPEC)
    @test MCP.uses_sessions(FAKE_SPEC)
    @test MCP.get_policy(FAKE_SPEC) === :legacy_sse
    @test MCP.delete_policy(FAKE_SPEC) === :session
    @test !MCP.allows_batch(FAKE_SPEC)
    @test MCP.emits_structured_content(FAKE_SPEC)
    @test MCP.shows_resource_icons(FAKE_SPEC)
    @test MCP.not_found_code(FAKE_SPEC) == MCP.MCP_RESOURCE_NOT_FOUND
    for tag in SHARED_METHOD_TAGS
        @test MCP.method_available(FAKE_SPEC, Val(tag))
    end
    for tag in LEGACY_ONLY_METHOD_TAGS
        @test MCP.method_available(FAKE_SPEC, Val(tag))
    end
    for tag in MODERN_ONLY_METHOD_TAGS
        @test !MCP.method_available(FAKE_SPEC, Val(tag))
    end

    # Unknown methods still yield -32601 under a new revision.
    body, status = MCP.dispatch(Oxygen.Core.ServerContext(), nothing, 1, "no/such",
                                Dict{String,Any}(); spec=FAKE_SPEC)
    @test status == 404
    @test body["error"]["code"] == MCP.MCP_METHOD_NOT_FOUND
end

end
