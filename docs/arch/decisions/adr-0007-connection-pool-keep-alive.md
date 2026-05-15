# ADR-0007 — Connection pool and persistent keep-alive for the Kubernetes API client

- Status — Accepted (ratified 2026-05-15)
- Refined by — ADR-0029, ADR-0035
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — performance, kubernetes, swiftnio, connection-pool

> **Refinement note (2026-05-15).** ADR-0025 supersedes the shared-client model chosen here (Option
> A — shared `HTTPClient` with per-cluster configuration overlays). Each cluster now materialises a
> dedicated `HTTPClient` and `EventLoopGroup` inside its own `ClusterSessionActor` (ADR-0025 Option
> C). All pool parameters defined in this ADR (`idleTimeout = 45s`,
> `concurrentHTTP1ConnectionsPerHostSoftLimit = 8`, `timeout.connect = 10s`, `timeout.read = 30s`,
> `httpVersion = .automatic`, `proxy = .environment`) carry forward unchanged — they apply
> per-session rather than globally. The watch-stream dedicated client rule also carries forward
> per-session.

> **Refinement note — I/O selector (2026-05-15).** ADR-0029 pins the kernel I/O event notification
> mechanism for all HTTP pool operations to `kqueue(2)` on macOS via SwiftNIO
> `MultiThreadedEventLoopGroup`. Each `ClusterSessionActor` creates its own group (see ADR-0025);
> the kqueue FD count per session equals `max(2, ProcessInfo.activeProcessorCount / 4)` event loops.
> Pool socket readability and writability events are delivered via `EVFILT_READ` and `EVFILT_WRITE`
> filters; pool-idle timer reaping uses `EVFILT_TIMER`. No alternative selector (`select(2)`,
> `poll(2)`) is used.

## Context and problem statement

K8sManager performs many small Kubernetes API requests per minute — health probes, list operations
for the assistant's MCP tools, occasional watch streams. Establishing a fresh TLS connection per
request would dominate latency (typical TLS 1.3 handshake to a remote API server is 40–120 ms; cold
connections add DNS plus TCP costs on top). The SwiftkubeClient adapter chosen in ADR-0002 layers
over the `async-http-client` package, which exposes a configurable `HTTPClient.Configuration` with
an internal connection pool. We must codify the pool sizing, keep-alive timeouts, and the lifecycle
rules that keep the pool healthy across cluster switches and kubeconfig reloads.

## Decision drivers

- **Latency for interactive workloads** — sub-100 ms request times on a warm pool are required for
  the UI to feel snappy and for the assistant's tool calls to chain without visible delays.
- **Resource ceiling** — a desktop application with N clusters and occasional bursts should not hold
  hundreds of idle sockets; unbounded pool growth on multi-cluster switching is the failure mode to
  avoid.
- **Compatibility with API-server idle timeouts** — typical Kubernetes API servers (kube-apiserver
  default `--http-idle-timeout=90s`, AWS EKS and GKE proxies often 60s) close idle connections
  without warning; the client pool must reap before the server does.
- **Watch streams are special** — long-lived HTTP/1.1 chunked or HTTP/2 streams must not occupy
  general-purpose pool slots. Reserve a separate pool category or per-stream client.
- **Pool churn on cluster switching** — switching contexts must not close every pooled connection
  synchronously on the UI thread.

## Considered options

### Option A — Shared `HTTPClient` with per-cluster configuration overlays (chosen)

- **Pros** — single set of event loops, low resource ceiling, fast warm-pool latency, watch streams
  cleanly separated.
- **Cons** — overlay implementation is bespoke on top of `async-http-client`; one buggy overlay
  could leak across clusters if it mutates shared state.

### Option B — One `HTTPClient` per cluster

- **Pros** — perfect isolation; no shared state.
- **Cons** — N clusters × event-loop groups; significant memory overhead at idle; shutdown ordering
  complicates exit.

### Option C — `URLSession` per cluster with custom delegate

- **Pros** — Apple-supported transport; integrates with macOS networking diagnostics.
- **Cons** — HTTP/2 stream cancellation is awkward; watch-style long-poll handling on `URLSession`
  is brittle; loses SwiftkubeClient ergonomics.

## Pros and cons of the options

### Option A — Shared `HTTPClient` with per-cluster configuration overlays (chosen)

- Good, because a single event-loop group minimises idle thread count on a desktop app.
- Good, because warm-pool latency stays well below 80 ms for interactive Kubernetes API requests.
- Good, because watch streams are cleanly separated via a dedicated short-lived client, keeping
  general-purpose pool slots uncontaminated.
- Good, because pool parameters (`idleTimeout`, connection limits, timeouts) are centralised in one
  place and carry forward into per-session actors (ADR-0025 refinement).
- Bad, because per-cluster CA/cert overlays require a bespoke extension on top of `async-http-client`
  that must be maintained as the library evolves.

### Option B — One `HTTPClient` per cluster

- Good, because each cluster has perfect isolation with no risk of cross-cluster state leakage.
- Bad, because N connected clusters each spin up a full `MultiThreadedEventLoopGroup`, multiplying
  resident memory and FD usage proportionally.
- Bad, because shutdown ordering becomes complex when clusters are disconnected in arbitrary order.

### Option C — `URLSession` per cluster with custom delegate

- Good, because it uses Apple's supported transport, enabling macOS networking diagnostics (Network
  Framework Instrument, Charles Proxy).
- Bad, because HTTP/2 stream cancellation semantics on `URLSession` are brittle for long-running
  watch streams.
- Bad, because it loses SwiftkubeClient ergonomics and requires a parallel adapter implementation.

## Decision outcome

- Use one **shared `HTTPClient` instance per process**, owned by the `cluster_connectivity`
  infrastructure layer. The client uses a `MultiThreadedEventLoopGroup` sized at
  `max(2, ProcessInfo.activeProcessorCount / 2)` event loops.
- The default `HTTPClient.Configuration` is: `connectionPool.idleTimeout = .seconds(45)`,
  `connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = 8`, `timeout.connect = .seconds(10)`,
  `timeout.read = .seconds(30)`, `httpVersion = .automatic` (HTTP/2 when offered, HTTP/1.1
  otherwise), `proxy = .environment` (honour the user's HTTPS_PROXY).
- **Per-cluster client overlays** — each cluster materialises a thin `HTTPClient.Configuration`
  overlay carrying its certificate authority, client certificate (when applicable), and any custom
  `proxyShouldHandleAuthentication` hook. The underlying client is shared; configuration overlays
  are applied per request via `HTTPClientRequest.with(certificateAuthority:)` semantics provided by
  the adapter.
- **Watch streams** open a dedicated short-lived client per stream with
  `connectionPool.maxConcurrentRequestsPerConnection = 1`, `responseDecompression = .disabled`, and
  `idleTimeout = .hours(1)`. Stream cancellation closes the dedicated client, never the shared pool.
- **Pool reaping on context switch** — switching the active context does **not** close pooled
  connections to other clusters; the pool retains them up to `idleTimeout` so quick "switch back"
  returns to a warm pool. Closing the application calls `HTTPClient.shutdown()` exactly once on
  graceful exit.
- **Kubeconfig reload** — a reload invalidates only the entries whose cluster identifier was removed
  or whose CA changed. Per-cluster overlays for surviving clusters remain valid.
- **Observability** — the adapter exposes counters for pool size, active connections, requests in
  flight, and reaped connections. The counters power the assistant's diagnostic tools and a hidden
  diagnostics panel in `app_shell`.

### Consequences

- **Positive** — warm-pool request latency dominated by network round-trip rather than TLS
  handshake; cluster switching costs are amortised; resource ceiling is bounded by
  `clusters × concurrentHTTP1ConnectionsPerHostSoftLimit`.
- **Negative** — observability code grows by a few hundred lines; shared-client lifetime spans the
  entire process and requires careful shutdown on quit; per-cluster CA propagation requires a small
  extension on top of SwiftkubeClient.
- **Neutral** — HTTP/2 multiplexing on API servers that offer it (most managed offerings) cuts pool
  size effectively; the per-host soft limit then becomes an upper bound, rarely a steady-state
  value.

### Confirmation

- A synthetic test issues 100 sequential GETs against `/api/v1/namespaces` on a warm pool; p95 stays
  below 80 ms on a cluster within 50 ms RTT.
- A synthetic test switches between four clusters round-robin for five minutes; pool size never
  exceeds `4 × 8 = 32` HTTP/1.1 connections.
- A watch stream cancellation does not change the shared-pool size.
- An idle test of five minutes finds the pool reaping to zero connections after `idleTimeout` and
  re-establishing on demand.

## More information

- ADR-0002 — SwiftkubeClient adapter (this decision lives inside that adapter).
- ADR-0009 — MCP host plus in-process MCP server (the pool serves the MCP tool calls).
- ADR-0011 — Swift concurrency conventions (the pool is owned by an `actor` to serialise lifecycle
  operations).
