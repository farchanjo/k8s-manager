# ADR-0011 — Swift concurrency conventions for a fluid async UI

- Status — Accepted (ratified 2026-05-15)
- Extended by — ADR-0025, ADR-0029
- Refined by — ADR-0035, ADR-0037, ADR-0050 (OpenTabsActor added to actor ownership map)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — concurrency, swift, async-await, actors, performance

> **Extension note (2026-05-15).** ADR-0034 extends this ADR with three explicit additions: (1) the
> Observation framework (`@Observable` macro) is the exclusive UI reactivity mechanism — Combine is
> prohibited for new SwiftUI bindings; (2) `AsyncThrowingStream` is the canonical domain port output
> type for live data streams; (3) complex view-level state beyond `AsyncResource` uses explicit sum
> types following the `#EditorState` pattern from ADR-0030.

> **Extension note — kqueue I/O selector (2026-05-15).** ADR-0029 names the kernel I/O event
> notification mechanism that underlies the async I/O model described in this ADR. Every
> `async`/`await` operation that touches a socket, file, or timer ultimately routes through
> `kqueue(2)` on macOS — via SwiftNIO `MultiThreadedEventLoopGroup` for Kubernetes API channels, and
> via libdispatch `kqueue`-backed dispatch sources for `Task.sleep(for:)` and
> `ContinuousClock`-based timers. The ban on `DispatchQueue.main.async` for I/O and the ban on
> `Thread.sleep` in this ADR are direct consequences of keeping all I/O notifications on the kqueue
> path.

> **Extension note (2026-05-15).** ADR-0025 adds `ClusterSessionActor` to the actor ownership map
> defined in this ADR. One `ClusterSessionActor` instance is spawned per active cluster; it owns the
> cluster's `#ClusterSession` AggregateRoot (dedicated `HTTPClient`, `EventLoopGroup`, credential
> cache, watch stream registry, exec session registry, port-forward registry, terminal session
> registry, and per-cluster view state). All mutations to a cluster's session go through awaited
> method calls on its `ClusterSessionActor`. Sub-tasks are orchestrated via `withThrowingTaskGroup`
> so that actor cancellation tears down all child tasks in order without violating the
> `Task.detached` ban.

> **Extension note (2026-05-16).** ADR-0050 adds two actors to the ownership map: `OpenTabsActor` —
> owns the ordered list of open `DocumentTab` values across all clusters; owns the watcher-task
> registry keyed by `tabId`; exposes `AsyncStream<[DocumentTab]>` to the tab bar view model;
> persists tab state to the filesystem on every mutation. `ClusterStripActor` — owns the ordered
> list of `ClusterStripPin` values; exposes `AsyncStream<[ClusterStripPin]>` to the cluster strip
> view; persists pin order to `workspace/cluster-strip-pins.json`. Both actors are application-scope
> singletons (one per app instance, not per cluster). The sidebar tree is a read-only SwiftUI
> projection of both actors' state and must not call any mutating methods directly; it issues
> commands (e.g. `openTab`, `pinCluster`) to the respective actor.

## Context and problem statement

K8sManager's UX target is "fluid". Concretely — every interactive element renders within one frame
(16 ms) of an input; long operations (network calls, SQLite queries, LLM streams, MCP tool calls)
never block the main actor; cancellation is cooperative and predictable. The Swift Concurrency model
(async/await, actors, structured concurrency, `AsyncSequence`, task groups) is the tool of choice on
Swift 6 with strict concurrency mode enabled.

Without explicit conventions, the codebase risks the usual failures — actor reentrancy bugs,
accidental capture of `@MainActor` types inside `Task.detached`, leaking long-lived `AsyncSequence`
subscribers, and "spinning at 100% CPU" patterns from polling loops disguised as streams.

This ADR captures the conventions.

## Decision drivers

- **Swift 6 strict concurrency** — the project enables `-strict-concurrency=complete` and `Sendable`
  is enforced. The conventions must produce code that compiles cleanly under that setting.
- **One owner per state** — for each mutable piece of state, exactly one actor (or main actor) owns
  it; cross-actor access goes through awaited method calls.
- **Cancellation is observed** — every long-running task checks `Task.isCancelled` at safe points
  and propagates cancellation to downstream work.
- **No `Thread.sleep`, no `usleep`, no `DispatchQueue.main.async` in new code** — these are escapes
  from the concurrency model and hide bugs.
- **Streams over polling** — UI listens to `AsyncSequence` of domain events; the assistant streams
  via `AsyncThrowingStream`; the diagnostics panel observes counters via `AsyncStream`.

## Pros and cons of the options

### Option A — Swift Concurrency end to end (chosen)

- Good, because a single mental model for all async work eliminates context-switching between
  Combine and async/await across the codebase.
- Good, because SwiftUI's native integration with `async`/`await` and `@Observable` removes the need
  for Combine publisher chains for UI state propagation.
- Good, because Swift 6 strict concurrency mode (`-strict-concurrency=complete`) catches actor
  isolation violations and missing `Sendable` conformances at compile time, before they become
  runtime bugs.
- Good, because structured concurrency (task groups, cancellation propagation, `onTermination`
  handlers) gives predictable lifetime and resource cleanup without manual lifecycle management.
- Bad, because Swift 6 discipline (actor isolation, `Sendable`, avoiding `Task.detached`) requires
  discipline and careful integration with third-party libraries that predate strict concurrency.

### Option B — Combine

- Good, because Combine is battle-tested across the Apple ecosystem and has well-understood patterns
  for publisher composition and subscriber lifetime.
- Bad, because Apple's recommended migration path away from Combine toward Swift Concurrency means
  adopting Combine now is choosing the deprecated path in a greenfield project.
- Bad, because introducing both Combine and async/await creates a double mental model that
  complicates code review and onboarding.

### Option C — Hybrid (Concurrency for new code, Combine for existing third-party adapters)

- Good, because it allows pragmatic adoption of Combine where third-party adapters offer no
  async/await surface.
- Bad, because there is no Combine-only third-party adapter that the project must adopt; introducing
  Combine voluntarily creates a second reactive surface to maintain.
- Bad, because bridging Combine publishers into async sequences adds boilerplate (`.values`,
  `AsyncPublisher`) that obscures intent without providing correctness benefits.

## Decision outcome

### Actor ownership map (MVP+)

- **`MainActor`** — every SwiftUI view, view model, and observable state object lives on
  `MainActor`. View bodies and `@Observable` property mutations happen here.
- **`KubernetesPoolActor`** — owns the shared `HTTPClient`, per-cluster overlay map, and pool
  metrics (ADR-0007). Single writer; readers obtain immutable snapshots via async methods.
- **`PersistenceActor`** — owns the GRDB `DatabasePool`. Mutations pass through this actor; reads
  either go through the actor (for consistency-sensitive cases) or use a read-only `DatabaseReader`
  obtained via the actor (for fan-out queries).
- **`AssistantSessionActor`** — owns a single chat session's message log and tool-use buffer. One
  actor instance per open session; the session is the consistency boundary.
- **`MCPServerActor`** — owns the in-process MCP server's tool registry, policy cache, and wire log.
  Tool dispatch goes through this actor.
- **Domain services** — usually stateless `struct`s with `func`s that take their dependencies in.
  When they hold state, they are small `actor`s named `<Capability>Service`.

### Cancellation

- Every public async API on a port accepts a cancellation token implicitly via Swift's task
  cancellation. Implementations must check `Task.isCancelled` at the start of work and after each
  awaited call.
- Streaming operations (`reply(to:)` in `LLMProviderPort`, the MCP wire reader, watch streams in
  `cluster_connectivity`) use `AsyncThrowingStream` with a `onTermination` handler that releases
  held resources.
- UI-initiated cancellation propagates by cancelling the SwiftUI task — the underlying
  `Task.cancel()` reaches every awaited operation in the chain. No bespoke cancellation tokens.

### Structured concurrency

- Concurrent fan-out uses `withThrowingTaskGroup` (or `withDiscardingTaskGroup` when results are not
  needed). Detached tasks (`Task.detached`) are forbidden outside three named call sites (the
  application launch sequence, the periodic vacuum task, and the MCP server shutdown). Each call
  site carries a comment explaining why structured concurrency was insufficient.
- Fire-and-forget work uses `Task { @MainActor in ... }` or a named `actor` method; it never escapes
  the lifetime of its parent.

### Threading rules

- No `DispatchQueue` in new code. Existing infrastructure code (SwiftNIO event loops) is wrapped at
  the boundary; the wrappers return `async` values.
- No `Thread.sleep` or `usleep`. Periodic work uses `ContinuousClock`-backed `Task.sleep(for:)`
  inside an `actor`.

### Backpressure

- LLM streams consume `AsyncThrowingStream` with a small buffer (default 16 events) and apply
  `bufferingPolicy = .bufferingOldest(16)` for token deltas; usage and tool-use events use unbounded
  buffers because they are infrequent.
- SQLite reads use GRDB's `DatabaseReader.read` (snapshot reads) and do not block writers under WAL.

### Sendable hygiene

- Domain value types are `Sendable` where possible (final or immutable struct with `Sendable`
  fields).
- Reference types (entities with identity) are confined to a single actor; cross-actor sharing
  requires a `Sendable` projection (a value-typed read model).

### Consequences

- **Positive** — predictable lifetime and cancellation; minimal CPU at idle; no accidental
  main-thread blocking; first-class cancellation across the app.
- **Negative** — `Task.detached` ban and `Sendable` discipline require care, especially when
  integrating third-party dependencies that predate strict concurrency.
- **Neutral** — Swift 6 strict concurrency keeps maturing; conventions may tighten further once SE
  proposals land.

### Confirmation

- The build compiles with `-strict-concurrency=complete` and zero warnings.
- A code search for `Thread.sleep`, `usleep`, `DispatchQueue.main.async`, and `Task.detached`
  returns only the three documented `Task.detached` call sites.
- A UI smoke test holds 60 fps while the assistant streams a 4 000-token response on a 2018 MacBook
  Pro.
- A cancellation test cancels an in-flight LLM stream and asserts that the underlying HTTP request
  returns within 200 ms.

## Considered options

### Option A — Swift Concurrency end to end (chosen)

- **Pros** — single mental model; SwiftUI's native integration; strict-mode catches most concurrency
  bugs at compile time.
- **Cons** — requires Swift 6 discipline.

### Option B — Combine

- **Pros** — battle-tested.
- **Cons** — Apple's recommended migration path is Swift Concurrency; double mental model in a
  greenfield project.

### Option C — Hybrid (Concurrency for new code, Combine for

existing third-party adapters)

- **Pros** — pragmatic.
- **Cons** — there is no Combine-only third-party adapter that we must adopt; introducing Combine
  voluntarily creates a second surface to maintain.

## More information

- ADR-0006 — Defines the bounded contexts whose actors are listed here.
- ADR-0007 — `KubernetesPoolActor` owns the pool.
- ADR-0008 — Streaming contract for LLM providers.
- ADR-0009 — `MCPServerActor` owns the in-process MCP server.
- ADR-0010 — `PersistenceActor` owns the SQLite pool.
