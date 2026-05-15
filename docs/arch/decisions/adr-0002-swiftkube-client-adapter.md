# ADR-0002 — SwiftkubeClient as primary Kubernetes API adapter

- Status — Proposed; library set pinned by ADR-0019; exec plugin strategy refined by ADR-0018
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — kubernetes, client, adapter, hexagonal

> **Pinning note (2026-05-15).** The library set adopted for this adapter is pinned by **ADR-0019**
> (Adopted Swift libraries) — specifically `swiftkube/client` 0.26.0,
> `swift-server/async-http-client` 1.33.x, and `URLSessionWebSocketTask` (Foundation built-in) for
> exec/portforward channel framing. PATCH server-side apply is implemented as a custom adapter route
> over `async-http-client` because `swiftkube/client` does not yet expose it.
>
> **Exec plugin note (2026-05-15).** The exec-plugin port introduced here has been split into a
> family of native adapters by **ADR-0018** (AWS, GCP, Azure, OIDC). The original generic subprocess
> strategy is retained as a fallback adapter (`SubprocessExecCredentialAdapter`) for kubeconfig
> entries that reference unrecognised exec plugins.

## Context and problem statement

K8sManager (ADR-0001) is implemented in Swift on macOS 14+. The domain core defines a
`KubernetesApiPort` and `ClusterHealthProbePort`. We must choose the adapter that fulfils these
ports against real Kubernetes API servers without leaking transport details (HTTP, TLS, exec
credential plugins, watch streams) into the domain core.

The MVP scope (multi-cluster connectivity and context switching) only requires the ability to (a)
parse a kubeconfig file, (b) probe each cluster's health endpoint, and (c) optionally enumerate the
authenticated user via a lightweight `/version` or `/api` call. No resource listing, no watches, no
exec, no port-forward in this scope. However, the adapter choice should not foreclose those
capabilities in the next milestone.

## Decision drivers

- **Native Swift** — keep the adapter inside the Swift Package Manager graph; avoid spawning
  external binaries when possible.
- **Async/await** — adapter must expose Swift structured concurrency primitives, not delegates or
  completion handlers.
- **TLS and client-cert support** — kubeconfigs use `certificate-authority` bundles and frequently
  use `client-certificate` and `client-key` for auth; the adapter must speak modern TLS.
- **Exec credential plugins** — many enterprise kubeconfigs (AWS EKS, GKE, AKS, OIDC) use `exec:`
  blocks that shell out to a binary which prints a `ExecCredential` JSON. We need a strategy for
  these even if the MVP defers full support.
- **Roadmap fit** — future milestones add resource listing, watch, logs, exec; the adapter family
  must grow with the product.
- **Surface area we own** — fewer lines of TLS, HTTP/2, and watch code in our repository is better.

## Considered options

- **Option A** — SwiftkubeClient (`swiftkube/client`, community, async/await, SwiftNIO transport).
- **Option B** — Spawn `kubectl` as a subprocess and parse its output.
- **Option C** — Build directly on URLSession (and `URLSessionWebSocketTask` or NIO for watch).
- **Option D** — Hybrid — Option C for plain HTTP calls, fall back to `kubectl exec` for credentials
  provided via `exec:` plugins.

## Decision outcome

Chosen option — **Option A (SwiftkubeClient)**, because it is the only option that delivers
idiomatic Swift async/await, ships a typed model graph for core and named API groups, and keeps the
adapter inside the package manager so the binary remains self-contained.

The `exec credential plugin` gap (a known limitation of SwiftkubeClient) is mitigated by a
**dedicated exec-plugin port** in the domain core whose default adapter shells out to the configured
binary (e.g., `aws eks get-token`, `gke-gcloud-auth-plugin`, `kubelogin`) using Foundation
`Process`. This isolates the subprocess concern from the HTTP/TLS path and avoids the full `kubectl`
shell-out anti-pattern.

### Consequences

- **Positive** — single, typed client surface for all Kubernetes API calls; native concurrency; no
  external binary required for clusters authenticated by static `client-certificate` or `token`;
  smaller binary than embedding `kubectl`; future milestones (watch, logs, exec) supported by the
  same client family.
- **Negative** — exec credential plugins require a dedicated port and subprocess adapter;
  SwiftkubeClient is community-maintained and evolves on its own cadence; certain
  `apiextensions.k8s.io` CRDs may require dynamic decoding outside the generated type graph.
- **Neutral** — watch streams use SwiftNIO under the hood; keep an eye on long-lived connection
  stability for kubeconfigs whose tokens rotate.

### Confirmation

- The domain core compiles without importing SwiftkubeClient.
- All Kubernetes API calls cross a port boundary (`KubernetesApiPort.swift` defined in the domain
  core; the adapter implementation lives in the infrastructure layer).
- A test using a kubeconfig that points to a `kind` cluster with a static `client-certificate`
  succeeds without invoking any external binary.
- A test using a kubeconfig with an `exec:` block successfully delegates to the exec-plugin adapter
  and obtains a token.

## Pros and cons of the options

### Option A — SwiftkubeClient

- **Pros** — native Swift, async/await, typed models, SwiftNIO transport, active community, supports
  watch.
- **Cons** — exec credential plugins partially supported; community maintenance cadence; CRDs need
  dynamic decoding for non-generated types.

### Option B — `kubectl` subprocess

- **Pros** — zero code for auth, TLS, exec, watch; kubectl handles every kubeconfig field on Earth;
  minimal client surface.
- **Cons** — external runtime dependency; users must install kubectl separately; subprocess overhead
  per call; output parsing is fragile; notarized macOS apps shipped via Developer ID can call
  subprocesses but cannot bundle `kubectl` cleanly without signing it as part of the app; UX bug
  surface is large.

### Option C — URLSession-only

- **Pros** — zero third-party dependencies; maximum control; no community lock-in.
- **Cons** — TLS client-cert plumbing on URLSession is painful; watch streams require HTTP/2 push or
  chunked transfer; entire model graph must be hand-rolled; far more code than the project can
  amortise.

### Option D — Hybrid (URLSession + kubectl for exec)

- **Pros** — combines control of Option C with kubectl's auth coverage.
- **Cons** — two completely different code paths to maintain; same notarization friction as Option
  B; not justified by MVP scope.

## More information

- ADR-0001 — Application runtime (depends on Swift platform).
- ADR-0003 — Kubeconfig is read-only (constrains adapter to read paths).
- Follow-up — write an ADR for the exec credential plugin port when the first non-static auth
  backend is added.
