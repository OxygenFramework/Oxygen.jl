# MCP Resource Subscriptions + Generic Pub/Sub — Implementation Plan

Status: ready to implement. This document is self-contained: a new session can start
from here without the conversation that produced it. Delete it once the work lands.

## 1. Goal

Enable server-initiated push for MCP resources (and, naturally, list-changed
notifications) with two deliverables:

1. A protocol-free, reusable pub/sub core (`PubSub`) that future features can build on.
2. The MCP adapter: modern `subscriptions/listen` streams, legacy
   `resources/subscribe`/`unsubscribe`, and `notify_*` push APIs.

Out of scope: `notifications/tasks` (tasks extension), `notifications/message`
logging, retained/coalesced payloads, WebSocket adapters, and the bundled MCP
Explorer UI (that lives in another repo).

## 2. Protocol requirements

### Modern (2026-07-28)

- `subscriptions/listen` request with `params.notifications` filter:
  `toolsListChanged` / `promptsListChanged` / `resourcesListChanged` (bools) and
  `resourceSubscriptions` (array of URI strings).
- The response is a long-lived **SSE stream on the same POST**. Its **first
  message must be** `notifications/subscriptions/acknowledged`, carrying
  `params.notifications` = the honored subset and
  `params._meta["io.modelcontextprotocol/subscriptionId"]` = the listen request id.
- Every subsequent message carries the same `subscriptionId` in `_meta`.
- Filter semantics: a server **MUST NOT** send notification types the client did
  not request. Types the server cannot deliver are omitted from the ack.
- Cancellation: HTTP = close the SSE stream; stdio = `notifications/cancelled`
  referencing the listen request id (stdio shares one output channel, so the
  subscription id is the demux key). Cancellation is **not** honored in-band for
  HTTP streams (a notification can arrive on any connection; honoring it would
  let one client kill another client's stream by guessing its id).
- Graceful server close: send the JSON-RPC response to the listen request
  (`result: {resultType: "complete", _meta: {subscriptionId, serverInfo}}`) before
  closing the stream.
- Capability: `resources: {subscribe: true, listChanged: true}`, plus
  `tools/prompts: {listChanged: true}` when list changes are announced.

### Legacy (2025-06-18 / 2025-11-25)

- `resources/subscribe` / `resources/unsubscribe` with `params.uri`, empty result.
  Idempotent.
- `notifications/resources/updated` `{uri}` delivered on the server→client channel:
  stdio stdout, or the HTTP GET SSE stream (`handle_get` in `src/mcp.jl`).
- List-changed notifications `notifications/{kind}/list_changed` are global (not
  per-subscription) and gated on the advertised capability.
- Single-session semantics are acceptable (the reference implementation is
  single-session too): one `wire_subscriptions` set per server. Document that
  legacy HTTP is a single-client channel.

## 3. Reference implementation findings

The official Julia SDK, `ModelContextProtocol.jl` (server side), already solves this.
A clone was available at
`/var/folders/5l/pwr8rhbj4wnfpwm_crsw2n380000gn/T/opencode/ModelContextProtocol.jl`
(local tmp, may not persist; the findings below are the durable part). Its relevant
files:

- `src/features/subscriptions.jl`: `SubscriptionFilter`, `SubscriptionRecord`,
  `SubscriptionRegistry`, `parse_subscription_filter`, `filter_to_wire`,
  `filter_wants`, `MAX_RESOURCE_SUBSCRIPTIONS = 256`.
- `src/protocol/subscriptions.jl`: `handle_subscriptions_listen` (ack+register
  under one lock), `broadcast_subscription_notification`, `notify_list_changed`,
  `notify_resource_updated`, `cancel_subscription!`, `close_subscriptions!`,
  `MAX_SUBSCRIPTIONS = 64`, `MAX_SUBSCRIPTION_ID_LENGTH = 128`.
- `src/transports/base.jl` / `http.jl`: transport hooks `send_notification`,
  `deliver_notification` (returns `Bool` for pruning), `route_alive`,
  `capture_response_route`; per-request response channels; `LISTEN_BACKLOG_CAP = 256`.
- `src/transports/stdio.jl`: a shared `write_lock` serializing all stdout writes.
- `src/core/server.jl`: in-process callback observers `subscribe!`/`unsubscribe!`,
  graceful close on loop exit.

Rules worth copying verbatim (they are subtle and battle-tested):

1. **Ack-then-register under the same lock that broadcasts take.** Guarantees no
   notification can precede the ack and no half-registered stream is visible.
2. **Honored-subset gating** on server capabilities; malformed filters rejected
   with `-32602`; unknown filter keys ignored; at least one type must be requested.
3. **Capacity + sweep**: cap active listens; sweep dead streams at registration
   *and* on every broadcast (a quiet server must not leak the cap); reject
   duplicate listen ids (load-bearing on stdio); cap id length.
4. **Load-shed, don't buffer forever**: bounded backlog per listen; on overflow
   close the stream (already-buffered frames stay drainable) and prune.
5. **Cancellation security rule**: only routeless (stdio) streams are cancellable
   via `notifications/cancelled`.
6. **Graceful shutdown under the broadcast lock**: deliver the final result, then
   empty the registry, so nothing can be written after the closing result.
7. **Legacy gating**: deliver only when `initialized && negotiated_version !== nothing`
   and the capability is declared; copy-on-write the subscription set so readers
   see consistent snapshots.
8. **Stdio write lock**: responses and notifications share stdout.
9. **Keepalive writes are the only dead-peer detector** on SSE; the channel is
   closed in the consumer's `finally`, which is what prunes subscriptions.

The SDK's server loop differs from Oxygen (single loop + per-request response
channels). Oxygen already has per-request tasks and `EventStream`s, so the
equivalent is: a listen request owns an `EventStream` whose **channel doubles as
the broker subscription queue**. The broadcaster pushes into that channel; the
connection task's pump writes frames; `cancel_stream!` closing the channel prunes
the subscription. No route registry or task-local storage needed.

## 4. Design

### 4.1 Generic core — `src/pubsub.jl` (new module `PubSub`)

Include at `src/core.jl:30` (next to `streaming.jl`), `@reexport using .PubSub`,
so it is reachable as `Oxygen.Core.PubSub` without polluting `Oxygen`'s exports.

```julia
module PubSub

export Broker, Subscription, subscribe!, unsubscribe!, publish!, subscribers, drops, close_all!

mutable struct Subscription{T}
    id       :: String                 # unique id (uuid), for cancel/introspection
    label    :: String                 # topic/pattern, for logs
    matcher  :: Function               # (topic::String, value::T) -> Bool
    queue    :: Channel{T}             # per-subscriber bounded queue
    callback :: Union{Nothing,Function} # optional in-process observer
    drops    :: Threads.Atomic{Int}
    active   :: Threads.Atomic{Bool}
end

mutable struct Broker{T}
    lock     :: ReentrantLock
    exact    :: Dict{String,Vector{Subscription{T}}}  # exact-topic subscribers
    patterns :: Vector{Subscription{T}}               # regex/predicate subscribers
    cap      :: Int                                   # max active subscriptions
end

Broker{T}(; cap::Integer=256) where {T} = ...
Broker(; kwargs...) = Broker{Any}(; kwargs...)

# csize: bounded queue capacity. policy: :drop_newest | :drop_oldest | :disconnect.
# channel: optional pre-created queue (used for ack-before-register).
subscribe!(broker, topic::AbstractString; csize=64, policy=:drop_newest, callback=nothing)
subscribe!(broker, pattern::Regex; label="", csize=64, policy=:drop_newest, callback=nothing)
subscribe!(broker, predicate::Function; label="", csize=64, policy=:drop_newest, callback=nothing)
unsubscribe!(broker, sub)::Bool
publish!(broker, topic::AbstractString, value::T)::Int   # never blocks; returns deliveries
subscribers(broker)::Int
close_all!(broker)                                       # shutdown
Base.close(sub); Base.isopen(sub); drops(sub)

end
```

Semantics:

- **Delivery** happens under `broker.lock` using non-blocking writes only:
  `tryput!`; on failure apply the policy (`:drop_newest` → count drop;
  `:drop_oldest` → `trytake!` then `tryput!`; `:disconnect` → `close(queue)` and
  prune). Holding the lock during delivery is deliberate: it makes ordering
  (ack-first, close-last) a lock invariant rather than a race to reason about.
- **Pruning**: closed/dead subs are removed opportunistically on publish, on
  `subscribers`, and on `subscribe!`. Empty `exact` vectors are deleted.
- **Lock ordering** (document in the module header): `broker.lock` may be held
  while doing channel ops; never take a consumer/transport lock while holding
  `broker.lock`.
- **Callbacks** run on the publisher's task after the queue write, outside the
  lock (snapshot, then invoke) so a callback may `unsubscribe!` itself. Errors are
  logged and swallowed.
- Topic matching: exact string dict fast path plus regex/predicate scans.

Simplest correct `subscribe!` with a pre-created channel (needed for the ack race):
create the channel, write the ack, then call `subscribe!(...; channel=...)`.

### 4.2 MCP adapter — `src/mcp/subscriptions.jl` (new)

Include after `resources.jl` in `src/mcp.jl` (line ~87).

**Event model** (payloads in the MCP broker):

```julia
# A server-push notification. `uri` is set for resource updates so filters can
# match without decoding `params`.
struct SubscriptionNotification <: StreamEvent
    method :: String                       # e.g. "notifications/resources/updated"
    params :: Dict{String,Any}
    uri    :: Union{Nothing,String}
end

# The broker payload is StreamEvent so a listen stream's queue can be the
# subscription queue verbatim (no bridge task).
const MCPBroker = PubSub.Broker{StreamEvent}
const META_SUBSCRIPTION_ID = "io.modelcontextprotocol/subscriptionId"
```

`MCPContext` cannot reference `MCPBroker` (include order: `context.jl` precedes
`mcp.jl`), so the broker is created lazily by the adapter and stored as
`Ref{Any}`; see §4.3. The alias above is used throughout the MCP module.

**Filter**:

```julia
Base.@kwdef struct SubscriptionFilter
    tools_list_changed     :: Bool = false
    prompts_list_changed   :: Bool = false
    resources_list_changed :: Bool = false
    resource_uris          :: Set{String} = Set{String}()
end

parse_subscription_filter(notifications) :: Union{SubscriptionFilter,String}
    # - object; bools strictly Bool; resourceSubscriptions array of strings,
    #   le 256 entries; at least one type requested; unknown keys ignored
filter_wants(filter, event) :: Bool
    # method dispatch + uri membership
filter_to_wire(filter) :: Dict{String,Any}
    # honored subset, resourceSubscriptions sorted
honored_filter(ctx, requested) :: SubscriptionFilter
    # mask by server capabilities (always all true here, but keep the seam)
```

Constants (mirroring the reference):

```julia
const MAX_LISTEN_SUBSCRIPTIONS   = 64
const MAX_RESOURCE_SUBSCRIPTIONS = 256
const MAX_SUBSCRIPTION_ID_LENGTH = 128
const LISTEN_BACKLOG_CAP         = 256
const LEGACY_NOTIFICATION_CAP    = 1000   # GET/stdout sink queue
```

**Listen call** (returned by dispatch; sibling of `StreamedCall`):

```julia
struct ListenCall
    stream :: EventStream        # channel is the broker subscription queue
    id     :: Any                # JSON-RPC id, also the subscriptionId
end
```

The transport return-type unions (`dispatch` at `src/mcp.jl:151`, `process` at
`:230`, `handle` at `:350`, `stdio_loop` at `:566`) grow by one member:
`Union{Dict{String,Any},StreamedCall,ListenCall}` (or a small union alias
introduced in `mcp/streams.jl`).

Constructor (`listen_call(ctx, req, id, params)`):

1. Parse + validate the filter (`-32602` on violation).
2. Validate id type (`String`/`Int`) and length (`-32600`).
3. Capacity precheck + sweep dead records under the listen lock
   (`-32603` when at `MAX_LISTEN_SUBSCRIPTIONS`; duplicate id → `-32600`).
4. `channel = Channel{StreamEvent}(LISTEN_BACKLOG_CAP)`.
5. Enqueue the ack **first** into `channel`.
6. `sub = PubSub.subscribe!(broker, e -> filter_wants(honored, e);
                           channel=channel, policy=:disconnect, label="listen:<id>")`.
7. Register `id => record(sub, channel, stream)` in `ctx.mcp.listens`.
8. Return `ListenCall(EventStream(channel, ListenState(...)), id)`.

**Broadcast + notify**:

```julia
broadcast(ctx, event::SubscriptionNotification) :: Int   # publish and count
notify_resource_updated(ctx, uri) :: Int
notify_list_changed(ctx, kind)    :: Int                  # :tools | :prompts | :resources
close_listens!(ctx)                                       # graceful shutdown
cancel_listen!(ctx, id)                                   # stdio cancellation
```

`notify_list_changed` is also called from `store_tool!`, `register_prompt!`, and
`register_resource!` so the advertised `listChanged` capability is truthful.
Boot-time registrations have no subscribers, so this is free.

### 4.3 Context state — `src/context.jl`

Add to `MCPContext` (keeps include order unconstrained by using `Ref{Any}` for the
broker, matching the existing `app_context::Ref{Any}` convention):

```julia
broker               :: Ref{Any}                  = Ref{Any}(nothing)  # lazy MCPBroker
subscriptions_lock   :: ReentrantLock             = ReentrantLock()
legacy_subscriptions :: Set{String}               = Set{String}()      # wire_subscriptions
listens              :: Dict{String,Any}          = Dict{String,Any}() # id => listen record
```

`MCPContext` is immutable, but `Ref`/`Set`/`Dict`/lock are mutable. Guard the
`listens` dict and `legacy_subscriptions` with `subscriptions_lock`. The broker is
created lazily under the same lock:

```julia
function broker(ctx)
    b = ctx.mcp.broker[]
    b === nothing || return b::MCPBroker
    lock(ctx.mcp.subscriptions_lock) do
        b = ctx.mcp.broker[]
        b === nothing || return b
        b = MCPBroker(; cap=MAX_LISTEN_SUBSCRIPTIONS)
        ctx.mcp.broker[] = b
        return b
    end
end
```

### 4.4 Transport integration

**HTTP modern listen** (`src/mcp.jl`)

- `dispatch`: `subscriptions/listen` → modern only (`-32601` in legacy, same
  pattern as `initialize` at `src/mcp.jl:156`). Build via `listen_call`.
- `handle` (`src/mcp.jl:350`): `body isa ListenCall` → `stream_listen_call`.
- `stream_listen_call`: requires `Accept: text/event-stream` (else `400` JSON-RPC
  error; modern listen is SSE-only); writes SSE headers; pumps with keepalives;
  a `FinalEvent` (graceful close) is written as the JSON-RPC response frame;
  `SubscriptionNotification` values are serialized with
  `serialize_listen_event(subscription_id, event)`, which copies `params` and
  **merges** `_meta.subscriptionId` into any existing `_meta` (the ack's params
  already carry it, so don't overwrite the whole `_meta` dict); on write
  failure/disconnect `finally cancel_stream!(stream)` (closes the queue → broker
  prunes) and remove the `listens` entry.
- **Prefactor**: extract the SSE write/keepalive loop from `stream_call`
  (`src/mcp.jl:396-479`) into a shared helper so the listen variant doesn't fork
  the keepalive/disconnect behavior.
- `handle_get` / `stream_notifications` (`src/mcp.jl:500-561`) are legacy-only
  (modern GET is 405): register a broker subscription whose predicate checks
  `uri in ctx.mcp.legacy_subscriptions`, then forward matched events as SSE
  `data:` frames alongside the existing keepalives; unsubscribe on disconnect.
  This is the legacy HTTP delivery path.
- Legacy methods `resources/subscribe`/`resources/unsubscribe`: dispatch branches
  that mutate `legacy_subscriptions` under the lock and return `{}`; modern era
  gets `-32601`.

**stdio** (`src/mcp.jl:566-620`)

- Introduce a per-loop `StdioNotifier`:

  ```julia
  mutable struct StdioNotifier
      output :: IO
      lock   :: ReentrantLock             # shared by respond and notifications
      tasks  :: Vector{Task}
      subs   :: Vector{PubSub.Subscription}
  end
  ```

  `respond(notifier, body)` becomes the single locked write path (`JSON.print`,
  newline, flush) — mirroring the reference SDK's `write_lock`.
- `stdio_loop` creates the notifier; `body isa ListenCall` registers it (one
  forwarding `@async` per listen: `take!` queue → `serialize_listen_event` →
  locked write) instead of `stream_stdio_call`.
- Legacy stdio: create one broker subscription at loop start with predicate
  `uri in legacy_subscriptions`; forward matched events (plain
  `notifications/resources/updated` without `_meta`) under the write lock.
  Gate delivery on a completed handshake: today `ctx.mcp.session_version[]` has a
  non-nothing default, so add a `handshake_complete :: Ref{Bool}` (set in
  `initialize_result`) and require `initialized[] && handshake_complete[]`.
  `notifications/initialized` alone is not proof of a handshake.
- `notifications/cancelled` in `process` (`src/mcp.jl:230-247`): on stdio only,
  look up the listen id in `ctx.mcp.listens` and `cancel_listen!`. No response.
- On EOF (`finally`): cancel all listen subscriptions/tasks and close the notifier.

**Scripting invariants**

- Ack is enqueued before registration; registration and all delivery happen under
  `broker.lock`, so ack-first and close-last are guaranteed.
- A `notify_*` call from inside a tool handler must never land on that request's
  progress stream: listen/legacy consumers are separate broker subscribers, so
  this falls out naturally. Add a regression test.

### 4.5 Public API (`src/methods.jl`, exported in `src/Oxygen.jl`)

```julia
notify_resource_updated(uri::AbstractString)::Int
notify_resources_changed()::Int
notify_tools_changed()::Int
notify_prompts_changed()::Int
```

Wrappers over `Oxygen.Core.MCP.notify_*` using `CONTEXT[]`, exactly like
`tool`/`prompt`/`resource` wrappers; `@oxidize` modules and `instance()` apps get
per-instance behavior for free because `methods.jl` is re-included.

Optional (phase 5): in-process observers `subscribe_resource(uri, callback)` /
`unsubscribe_resource(uri, callback)` over `PubSub` callbacks. The reference SDK
has `subscribe!`/`unsubscribe!`; name them explicitly here to avoid clashing with
the generic core's `subscribe!`.

### 4.6 Capabilities (`src/mcp.jl:96`)

```julia
# modern
"tools"     => Dict("listChanged" => true)
"prompts"   => Dict("listChanged" => true)     # when prompts exist
"resources" => Dict("subscribe" => true, "listChanged" => true)  # when resources exist
# legacy keeps the same fields (booleans), matching current style
```

If any notification kind is not implemented yet when a phase lands, advertise
`false` for it and let `honored_filter` mask it — the ack is the honest source.

## 5. File-by-file summary

| File | Change |
|---|---|
| `src/pubsub.jl` | New module: `Broker`, `Subscription`, `subscribe!`, `unsubscribe!`, `publish!`, policies, callbacks |
| `src/core.jl` | Include + reexport `PubSub` (~line 30); `terminate` (line 243) calls `MCP.close_listens!(ctx)` before closing the server |
| `src/context.jl` | `MCPContext` fields for broker, lock, legacy set, listens, handshake flag |
| `src/mcp/subscriptions.jl` | New adapter: event type, filter parse/serialize, listen/publish/cancel/close, serializers |
| `src/mcp.jl` | Include adapter; dispatch branches; `ListenCall` routing in `handle`/`stdio_loop`; `process` cancellation; capabilities; shared SSE helper |
| `src/mcp/tools.jl`, `src/mcp/prompts.jl`, `src/mcp/resources.jl` | Call `notify_*_changed` after storing a registration |
| `src/methods.jl` | `notify_*` wrappers (after the resource section, ~line 465) |
| `src/Oxygen.jl` | Export `notify_resource_updated`, `notify_resources_changed`, `notify_tools_changed`, `notify_prompts_changed` (line 57) |
| `test/pubsubtests.jl` | New core tests |
| `test/mcp_subscriptiontests.jl` | New MCP tests |
| `test/runtests.jl` | Include both after `mcp_resourcetests.jl` (line 48) |
| `docs/src/tutorial/mcp.md`, `README.md`, `demo/mcpdemo.jl` | Docs + demo (mutation tool calls `notify_resource_updated`) |

## 6. Implementation phases

Each phase must leave `julia --project=. -e 'using Pkg; Pkg.test()'` green.

### Phase 1 — `PubSub` core

- [x] `src/pubsub.jl` with the API from §4.1
- [x] `test/pubsubtests.jl`: fan-out to N, exact/regex/predicate, unsubscribe,
      `:drop_newest`/`:drop_oldest`/`:disconnect`, callback firing + error
      containment + self-unsubscribe, dead-sub pruning on publish/subscribe,
      capacity enforcement, `close_all!`, concurrent publish stress
      (`Threads.@spawn`, skip when `nthreads() == 1`)
- [x] Include in `src/core.jl` + `test/runtests.jl`

### Phase 2 — MCP adapter + stdio delivery

- [x] Events, filter parse/honored/wire, constants, context state, lazy broker
- [x] `notify_*` functions + wrappers + exports
- [x] Auto `notify_*_changed` from registration functions; capability updates
- [x] Legacy `resources/subscribe`/`unsubscribe` state (methods + dispatch)
- [x] `StdioNotifier` + `respond` write lock; `ListenCall` over stdio; modern ack,
      tagged delivery, filtering, `notifications/cancelled`, graceful close
- [x] `close_listens!(ctx)` wired into `terminate`
- [x] Tests: filter validation, honored subset, tagging, no-subscriber no-op,
      ack-before-broadcast (concurrent hammer, mirror the reference test),
      stdio filtering (`notify` of an unrequested type returns 0), cancellation,
      graceful closure, limits/id rules, discover capability advertisement,
      legacy stdio delivery + no-handshake → no delivery

### Phase 3 — HTTP modern listen

- [x] Extract the shared SSE pump helper from `stream_call`
- [x] `stream_listen_call`; `ListenCall` routing in `handle`; disconnect prune
- [x] Backlog load-shed test (slow reader → stream closed, buffered frames drain,
      record pruned)
- [x] Dead-route sweep test (varies from stdio: prune a disconnected HTTP listen)

### Phase 4 — Legacy HTTP + hardening

- [x] GET SSE sink over the broker with `legacy_subscriptions` predicate
- [x] Legacy `notifications/{kind}/list_changed` broadcast on the GET sink
      (global, so broadcast is correct; no per-session split needed)
- [x] Shutdown ordering test: graceful listen result arrives before the transport
      closes; nothing is delivered after
- [x] Single-client legacy HTTP documented in the tutorial

### Phase 5 — Polish (optional)

- [x] In-process observers (`subscribe_resource`/`unsubscribe_resource`)
- [x] Extra notify API sugar / demo
- [x] Docs: mcp.md "Subscriptions" section, README bullet, demo tool that mutates
      `PLACES` and calls `notify_resource_updated`

## 7. Test-plan details

Follow existing conventions (`test/mcptests.jl`): one `module` per file, `using
Oxygen; @oxidize`, `const MCP = Oxygen.Core.MCP`, per-file `HTTP.Client`,
`PORT` for the primary server (files are sequential), `PORT + 6` for any second
server (PORT+1/+3/+4/+5 are taken by other suites).

Scenarios to cover explicitly, grouped:

**Core** — delivery counts, policy behavior, `Base.n_avail(queue)` assertions for
`:disconnect` (buffered items stay drainable), callback isolation.

**Modern HTTP** — first SSE frame is the ack; ack honored subset excludes types
the server did not advertise; update frames carry `subscriptionId`; two concurrent
listens on one server each get only their types; wrong/missing `Mcp-Method`/
`Mcp-Protocol-Version` still rejected; cancelled-by-disconnect prunes the record
(assert `subscribers(broker) == 0` eventually); malformed filter → `-32602`;
over-limit URIs → `-32602`; duplicate id → `-32600`; capacity → `-32603`.

**stdio** — ack/notifications are newline JSON with `subscriptionId`; interleaving
with ordinary responses is line-atomic; `notifications/cancelled` ends the stream
and prunes; EOF closes listeners; write lock keeps lines intact under concurrent
notifies.

**Legacy** — `resources/subscribe` result `{}`; updates only for subscribed URIs;
`unsubscribe` stops delivery; no `initialize` → no delivery (gated on
`initialized && handshake_complete`); `list_changed` gated on capability; modern
request of `resources/subscribe` → `-32601`.

**Regression** — a `notify_*` call inside a `tools/call` handler must not appear
on that call's progress SSE stream; `resetstate()` clears subscriptions and
listens; instance isolation (`instance()` broker is per-context).

## 8. Decisions already made

- Generic core is a broker over per-subscriber `Channel`s; channels are the queue
  primitive (blocking `take!` + `close` semantics + `pump_stream` integration).
- Delivery is non-blocking. `:drop_newest` is the core default; MCP listens use
  `:disconnect` with `LISTEN_BACKLOG_CAP` (matching the reference SDK).
- Modern ack/register happen under one lock; ack is written first.
- Cancellation via `notifications/cancelled` only for stdio; HTTP cancels by
  stream close.
- Legacy is single-session (matches the reference); no `Mcp-Session-Id`.
- `listChanged` is auto-published by registration functions.
- In-process callbacks and the Explorer UI are out of the critical path.

## 9. Open questions

1. Name of the generic module/API surface (`PubSub` vs `Topics`)? Current doc uses
   `PubSub`; the names are internal to `Oxygen.Core` so low risk.
2. Should `notify_*` return the delivery count (reference does) or `nothing`?
   Recommendation: `Int` for testability.
3. Should modern `subscriptions/listen` without `Accept: text/event-stream` be
   `400`, or should the transport force SSE regardless of Accept? Recommendation:
   `400` (modern spec expects SSE; forcing avoids hanging non-SSE clients).

## 10. Verification

```bash
# full suite
julia --project=. -e 'using Pkg; Pkg.test()'

# focused run while iterating (module drivers in the opencode tmp dir follow this pattern)
julia --project=. /path/to/driver.jl
```

Current MCP test suites for reference: `test/mcptests.jl`,
`test/mcp_streamtests.jl`, `test/mcp_router_tests.jl`,
`test/mcp_resourcetests.jl`; runtests includes them at lines 45-48.

## 11. Implementation notes (landed)

All phases landed; `test/pubsubtests.jl` and `test/mcp_subscriptiontests.jl`
are included in `test/runtests.jl` and the full `Pkg.test()` suite is green.
Notes where the implementation had to depart from the sketch:

- Julia 1.11/1.12 have no public `tryput!`/`trytake!` for `Channel`s. The
  PubSub core implements non-blocking puts/takes itself by taking the channel's
  own lock (`lock(c::Channel)`), checking capacity/readiness under it, and
  mutating through `put!`/`take!`; consumers only remove items, so the checks
  cannot be overtaken. Note `Base.isfull` is 1.12-only (the first iteration
  used it and broke delivery on 1.11), so the put path compares
  `length(channel.data)` against `channel.sz_max` directly; the full suite now
  runs on both 1.11 and 1.12.
- `legacy_event_wanted` takes `subscriptions_lock` while the broker lock is
  held (broker lock → context lock ordering, documented in
  `src/mcp/subscriptions.jl`). Nothing may acquire the broker lock while
  holding `subscriptions_lock`; `listen_call` therefore subscribes before
  registering its record.
- The MCP broker cap is shared with the legacy sinks. Capacity errors are
  caught: a listen surfaces `-32603`, a legacy HTTP GET gets `503`, and the
  stdio legacy sink is disabled with a warning.
- `close_listens!` uses a non-blocking enqueue for the closing result: if a
  backlog is full the stream degrades to an abrupt close instead of blocking
  shutdown.
- Phase 5's in-process observers (`subscribe_resource`/`unsubscribe_resource`)
  were not implemented; the `PubSub` callback seam they need is in place.
  Docs (`docs/src/tutorial/mcp.md`, `README.md`) and `demo/mcpdemo.jl` cover the
  public `notify_*` API.

This plan can be deleted once the branch is merged.
