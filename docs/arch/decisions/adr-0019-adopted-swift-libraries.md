# ADR-0019 — Adopted Swift libraries inventory

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — dependencies, swift, spm, libraries, audit

## Context and problem statement

K8sManager is implemented in Swift 6 strict-concurrency mode on macOS 14+. The project spans
multiple functional domains: Kubernetes API access, LLM provider integration, MCP host
functionality, Helm chart parsing and rendering, cloud credential resolution, local persistence, and
observability. Each domain requires third-party or Apple-platform libraries.

Before any library enters the Swift Package Manager dependency graph it must be evaluated against a
consistent set of criteria: licence compatibility with a commercial Developer-ID distribution, Swift
6 language mode compliance or a clear upgrade path, community maintenance health, SSWG (Swift Server
Workgroup) adoption tier where applicable, and the absence of transitive dependencies that violate
the hexagonal architecture contract (domain core targets must not import infrastructure libraries
directly).

This ADR records the outcome of the library audit conducted in May 2026, closes the selection for
the initial release milestone, and documents the risk profile and mitigation for each adoption.

A tier classification is used throughout this document:

- Tier A: Swift 6 strict concurrency clean, actively maintained, production-proven in comparable
  projects or SSWG Incubating/Graduated.
- Tier B: functional and well-maintained but not yet fully Swift 6 language mode; requires
  `@preconcurrency import` at the adapter boundary.
- Tier C: functional but with maintenance uncertainty or missing features; requires a mitigation
  plan.
- Tier D: archived or deprecated; use avoided or replaced.

## Decision drivers

- All adopted libraries must be compatible with Apache 2.0 or MIT licences to allow commercial
  distribution under Developer ID.
- Domain core targets must compile without importing any library from the K8s, Auth, Storage, or
  HTTP infrastructure groups. The hexagonal constraint is enforced at the Package.swift dependency
  graph level.
- Swift 6 language mode (`-language-mode 6` and `-strict-concurrency=complete`) must produce zero
  warnings and zero errors across all adopted libraries when accessed through their designated
  adapter targets.
- Libraries with Tier B rating are accepted only with an explicit wrapper module strategy that
  isolates `@preconcurrency` imports.
- No library in Tier D may be used for new functionality. Archived libraries may only appear in the
  "rejected" section as documentation.
- The total number of direct SwiftPM dependencies must remain manageable for a two-person team:
  transitive graph complexity is a maintenance cost.

## Considered options

- Option A — Adopt the specific versioned set documented in this ADR, sourced from the May 2026
  audit.
- Option B — Adopt community-recommended defaults without a structured audit (informal approach).
- Option C — Use only Apple-platform built-in frameworks (Foundation, Security, Network, CryptoKit)
  and write all protocol implementations from scratch.

## Decision outcome

Chosen option: Option A — the structured audit-sourced inventory defined in this ADR.

Option B is rejected because it produces an inconsistent dependency set that is difficult to reason
about across a team and over time. Without a formal selection record, decisions cannot be revisited
systematically when a library is archived or drops Swift 6 support.

Option C is rejected because the scope of implementation work required to replace battle-tested
libraries (SigV4 signing, OIDC, GRDB SQLite ORM, JWT verification, OCI registry protocol) without
third-party help would extend the timeline by 12 to 18 months and produce lower-quality
implementations of complex security-sensitive protocols.

### Consequences

Positive consequences:

- Every library in the dependency graph has a documented version, licence, tier rating, role, and
  risk mitigation. Future contributors can understand why each library was selected and what the
  upgrade path is.
- The tier classification makes risk visible: four libraries at Tier B require `@preconcurrency`
  wrapper treatment; one library category (GCP auth) has no viable external library and is built
  in-house.
- Locking specific versions in Package.resolved prevents transitive version drift between
  development machines and CI.

Negative consequences:

- Four libraries (SwiftAnthropic, MacPaw/OpenAI, MSAL, AppAuth-iOS) are not yet in Swift 6 language
  mode. They are accepted as Tier B because the alternatives are worse (reimplementing LLM provider
  SDKs or cloud auth flows). Each adapter target containing a Tier B library must expose only
  Sendable types and actors at its boundary to prevent concurrency unsafety from leaking into domain
  core.
- google-auth-library-swift (google/google-auth-library-swift) was archived by Google in
  October 2025. There is no replacement from Google. GCP credential resolution is therefore entirely
  a K8sManager maintenance responsibility from project inception.
- swiftkube/client does not implement PATCH with server-side apply semantics (Content-Type
  `application/apply-patch+yaml`). A custom implementation over async-http-client is required. This
  custom code becomes a maintenance risk if swiftkube/client adds SSA support in a future release
  and our adapter diverges from its API shape.
- Foundation Compression framework (gzip) is macOS-only. This is acceptable because K8sManager
  targets macOS 14+ exclusively, but it means any future cross-platform ambition requires
  replacement.

### Confirmation

- `swift package show-dependencies --format json` for the K8sManagerApp target must list every
  library in this ADR at the specified version or within the specified version range. No unlisted
  library may appear as a direct dependency of any domain core target.
- `swift build -Xswiftc -strict-concurrency=complete` must produce zero warnings in all targets.
- A licence compliance scan (e.g. swift-package-list) must confirm no GPL, LGPL, AGPL, or
  proprietary library appears in the transitive graph.

## Pros and cons of the options

### Option A — Structured audit-sourced inventory (chosen)

Positive:

- Documented rationale per library enables systematic future review.
- Tier classification makes technical debt (Tier B) explicit and bounded.
- Version pinning ensures reproducible builds across CI and developer machines.

Negative:

- Requires upfront audit time (approximately 2 weeks).
- ADR must be updated when libraries are upgraded across a major version boundary or when tier
  ratings change.

### Option B — Informal community-recommended defaults

Positive:

- Fast: no structured audit process required.
- Relies on community consensus rather than internal evaluation.

Negative:

- No documented rationale for selections; difficult to revisit decisions.
- Swift 6 compliance status of libraries is not systematically verified before adoption.
- Inconsistent versioning across developer machines before Package.resolved is committed.

### Option C — Apple-platform built-in frameworks only

Positive:

- Zero external dependencies: no supply-chain risk, no licence review, no upstream maintenance
  dependency.
- Apple-provided frameworks are always Swift 6 compatible.

Negative:

- Reimplementing SigV4, OIDC, JWT, Helm YAML parsing, SQLite ORM, and OCI registry protocol from
  scratch adds 12 to 18 months to the timeline.
- In-house implementations of security-critical protocols (JWT, SigV4, TLS certificate chain
  validation) carry high risk of subtle bugs.
- Not realistic for a two-person team.

## More information

### Group: Kubernetes API access

`swiftkube/client` version 0.26.0, Apache 2.0, Tier B with fork-readiness contingency, Swift 6
strict.

- Role: primary adapter implementing `KubernetesApiPort` and `WatchPort`. Covers list, get, create,
  update, delete, patch (JSON merge patch), and watch operations for all standard Kubernetes API
  groups included in swiftkube/model.
- Gap: does not support PATCH with server-side apply (Content-Type `application/apply-patch+yaml`).
  This operation is required for the Helm native apply path (ADR-0015 Phase 2) and for resource
  mutations that must avoid field ownership conflicts.
- Mitigation: a custom `ServerSideApplyClient` struct in the `SwiftkubeClientAdapter` target issues
  PATCH requests directly over `swift-server/async-http-client` with the correct Content-Type. If
  swiftkube/client adds SSA support in a future release, the custom client is removed and the
  adapter delegates to the library.
- Maintenance risk: swiftkube/client had no release since October 2024 as of the May 2026 audit. It
  is a single point of failure for the Kubernetes API surface. The `KubernetesApiPort` abstraction
  isolates this risk: if the library becomes unmaintained the adapter target can be replaced with a
  direct `async-http-client` implementation or a fork without touching domain core. Fork-readiness
  contingency is active: a working fork clone is maintained at project inception.

`swift-server/async-http-client` version 1.33.x, Apache 2.0, Tier A.

- Role: used directly only in `SwiftkubeClientAdapter` for the SSA PATCH gap and in
  `PrometheusQueryAdapter` for Prometheus HTTP/1.1 range query calls. Must not be imported in any
  domain core target.

`URLSessionWebSocketTask` (Foundation built-in), Tier A.

- Role: implements the pods/exec channel framing protocol (v5.channel.k8s.io) for
  `WebSocketExecAdapter` and the pods/portforward protocol (portforward.k8s.io) for
  `WebSocketPortForwardAdapter`. Apple's URLSession handles TLS and HTTP upgrade automatically; only
  the binary framing layer is implemented in the adapter.

### Group: LLM provider integration

`jamesrochabrun/SwiftAnthropic` version 2.2.2, MIT, Tier B.

- Role: `AnthropicAdapter` — implements `LLMStreamingPort` for Anthropic Claude models. Uses
  `tool_use` blocks and ephemeral cache control for prompt caching.
- Swift 6 status: not yet in language mode `.v6` as of May 2026. The adapter target uses
  `@preconcurrency import SwiftAnthropic` and exposes only `Sendable` types and `actor`-isolated
  state at its boundary toward the `LLMProvider` domain core.
- Risk: library maintainer is a single individual. Mitigated by MIT licence allowing fork if
  maintenance lapses.

`MacPaw/OpenAI` version 0.4.9, MIT, Tier B.

- Role: `OpenAIAdapter` and `OpenAICompatibleAdapter` — the same library instance serves both by
  configuring `baseURL` and `host` to point to the target provider (OpenAI production, Ollama, LM
  Studio, vLLM, or any OpenAI-compatible endpoint). Supports both Responses API and Chat Completions
  API.
- Swift 6 status: same situation as SwiftAnthropic. Same wrapper strategy applies.

`modelcontextprotocol/swift-sdk` version 0.12.1, MIT, Tier A.

- Role: `MCPSwiftSDKAdapter` — implements the in-process MCP server described in ADR-0009.
  `InMemoryTransport` is used for the in-process channel; no network socket is opened for the
  in-process MCP server.

`Recouse/EventSource` version 0.1.8, MIT, Tier A.

- Role: SSE stream parser used as a fallback when a provider streams responses over Server-Sent
  Events rather than chunked JSON. Primary path for Anthropic uses SwiftAnthropic's built-in
  streaming; EventSource is used for providers where no Swift SDK exposes SSE parsing natively.

### Group: Helm chart management

`jpsim/Yams` version 6.2.1, MIT, Tier A, Swift 6 strict.

- Role: YAML parse and emit for kubeconfig loading (`YamsKubeconfigAdapter`) and for Helm
  `Chart.yaml`, `values.yaml`, and rendered manifest inspection (`HelmManagement` adapter targets).

`apple/swift-container-plugin` version 1.3.0, Apache 2.0, Tier B.

- Role: OCI registry client used in Helm Phase 2 (ADR-0015) to pull and push Helm chart artifacts
  stored with media type `application/vnd.cncf.helm.chart.content.v1.tar+gzip` and the chart config
  media type. Not used in Phase 1 MVP.

`mattt/JSONSchema` version 1.3.1, MIT, Tier B.

- Role: validates `values.schema.json` bundled with Helm charts against user-supplied values before
  rendering. Phase 2 only.

Foundation Compression framework (built-in macOS 14+), Tier A.

- Role: decompresses `.tgz` Helm chart release archives fetched from chart repositories or OCI
  registries. `NSData` with `DataCompressionAlgorithm.zlib` is used; the tarball layer is parsed
  with `swift-system` path utilities.

### Group: Authentication and cryptography

`soto-project/soto` version 7.14.0, Apache 2.0, Tier A, Swift 6 strict, SSWG Incubating.

- Role: AWS credential provider chain (environment, profile, shared credentials file) and SigV4
  request signing used by `AWSExecCredentialAdapter` (ADR-0018).

`AzureAD/microsoft-authentication-library-for-objc` (MSAL) version 2.11.0, MIT, Tier B.

- Role: Azure Entra ID (formerly Azure Active Directory) authentication for
  `AzureExecCredentialAdapter`. Covers device code flow, service principal with client secret, and
  service principal with client certificate.
- Swift 6 status: ObjC bridge; requires `@preconcurrency import MSAL` in the adapter module.

`openid/AppAuth-iOS` version 2.0.0 (macOS-compatible build), Apache 2.0, Tier B.

- Role: OIDC generic authorization code flow with PKCE for `OIDCExecCredentialAdapter`.
- Swift 6 status: ObjC-based; requires `@preconcurrency import AppAuth` wrapper.

`apple/swift-crypto` version 4.5.0, Apache 2.0, Tier A.

- Role: HMAC-SHA256 for SigV4 (via CryptoKit), and RSA signing for GCP service account JWT via the
  `CryptoExtras` product (`_RSA.Signing.RSAPrivateKey`). CryptoKit is available built-in on macOS
  14+; swift-crypto is adopted for CryptoExtras RSA which is not in CryptoKit.

`apple/swift-certificates` version 1.19.1, Apache 2.0, Tier A.

- Role: X.509 certificate parsing and chain validation in `SwiftkubeClientAdapter` for clusters with
  a custom CA bundle declared in the kubeconfig `certificate-authority-data` field.

`apple/swift-asn1` version 1.7.0, Apache 2.0, Tier A.

- Role: ASN.1 DER decode/encode used transitively by swift-certificates and directly when parsing
  PEM-encoded private keys for GCP service account credentials.

`vapor/jwt-kit` version 5.5.0, MIT, Tier A, SSWG Graduated.

- Role: JWT signing (RS256 for GCP service account, ES256 for OIDC client assertions) and JWT
  verification (ID token signature validation against JWKS in `OIDCExecCredentialAdapter`).

### Group: Editor and content rendering

`mchakravarty/CodeEditorView` version `0.16.x`, MIT, Tier B.

- Role: SwiftUI-native code editor widget with TreeSitter-based syntax highlighting used by the
  integrated MD / YAML / JSON editor surface (ADR-0030). Provides line-number gutter, bracket
  matching, and theme support. Wrapped behind a `CodeEditorPort` adapter to isolate the
  `@preconcurrency` import required by its delegate callbacks.
- Swift 6 status: not in language mode `.v6` as of May 2026. The adapter target uses
  `@preconcurrency import CodeEditorView` and exposes only `Sendable` closures and actor-isolated
  callbacks at its boundary.
- Risk: smaller community than mainstream editor libraries. Mitigated by MIT licence and the
  `CodeEditorPort` abstraction — a replacement (e.g. a future Apple-provided editor component) can
  be swapped in without touching domain core targets.
- Multi-cursor editing (ADR-0030) requires CodeEditorView 2.x which is not yet released as of May
  2026; the multi-cursor feature is deferred and not in MVP. The version pin remains `0.16.x` until
  2.x ships and is audited for Swift 6 compliance.

`apple/swift-markdown` version 0.6+, Apache 2.0, Tier A, Apple-maintained.

- Role: CommonMark parser for Markdown preview rendering in the integrated editor (ADR-0030).
  Provides a document AST that the preview renderer walks to produce attributed strings or HTML for
  `WKWebView`. No external renderer library is required; the adapter owns the AST-to-display
  conversion.
- Swift 6 status: Apple-maintained; language mode 6 compliant.

Xcode String Catalog (`.xcstrings`), built-in (macOS 14+ / Xcode 15+), Tier A, toolchain feature.

- Role: localisation source-of-truth for all user-visible strings (ADR-0033). Listed here for
  completeness; it is not a SwiftPM dependency. String keys are compiled into `.strings` files at
  build time by Xcode; runtime access is via `String(localized:)` and `LocalizedStringKey` in
  SwiftUI.

### Group: Local persistence and general utilities

`groue/GRDB.swift` version 7.10.0, MIT, Tier A.

- Role: SQLite ORM for all persistent domain state: conversation history, cluster metadata, provider
  configuration records. Requires Swift 6.1 or later (GRDB 7.x minimum). Target:
  `GRDBPersistenceAdapter`.

`apple/swift-log` version 1.12.0, Apache 2.0, Tier A, SSWG Graduated.

- Role: structured logging interface across all targets. Backend is a custom OSLog sink (os.Logger)
  in the `K8sManagerApp` target so that logs appear in Console.app.

`apple/swift-metrics` version 2.10.1, Apache 2.0, Tier A, SSWG Graduated.

- Role: emit-only metrics API. Domain core targets call `Counter`, `Gauge`, and `Timer` from
  swift-metrics. The `PrometheusQueryAdapter` target reads Prometheus data over HTTP; it does not
  use swift-metrics for the query path. A Prometheus push gateway backend for swift-metrics is a
  post-MVP feature.

`apple/swift-system` version 1.6.4, Apache 2.0, Tier A.

- Role: `FilePath` and file descriptor utilities used in kubeconfig path resolution, Helm chart
  tarball extraction, and credential file path handling.

`apple/swift-collections` version 1.5.0, Apache 2.0, Tier A.

- Role: `OrderedDictionary` and `Deque` used in the resource browser pagination state machine and
  the LLM message history ring buffer.

`pointfreeco/swift-dependencies` version 1.12.0, MIT, Tier A.

- Role: dependency injection framework. Adapter registrations are declared as `@Dependency` keys,
  allowing test targets to override concrete adapters with test doubles without modifying production
  wiring.

`pointfreeco/swift-concurrency-extras` (current release), MIT, Tier A.

- Role: `ActorIsolated`, `LockIsolated`, and `withMainSerialExecutor` test utilities. Used only in
  `*Tests` targets; not linked in the production application bundle.

### Built-in and in-house implementations

Foundation URLSession and URLSessionWebSocketTask are used directly for HTTP/1.1, HTTP/2, and
WebSocket connections. No external HTTP client library is exposed to domain core targets.

Prometheus query client: approximately 340 lines of Swift implementing the Prometheus HTTP API v1
range query and instant query endpoints. No public Swift library for this protocol exists with
acceptable Swift 6 and macOS 14 support as of May 2026. The client lives in
`PrometheusQueryAdapter`.

GCP credential resolution: implemented entirely in-house in `GCPExecCredentialAdapter` because
google-auth-library-swift was archived in October 2025. The implementation covers user credentials
refresh token exchange, service account RS256 JWT, and external account Workload Identity
Federation. Dependencies: vapor/jwt-kit (JWT sign), apple/swift-crypto CryptoExtras (RSA),
URLSession (HTTP token exchange).

ExecCredentialPort adapters for AWS, GCP, Azure, and OIDC are all in-house implementations as
described in ADR-0018. The subprocess fallback adapter (`SubprocessExecCredentialAdapter`) is also
in-house and wraps `Process` from Foundation with an explicit sandboxing caveat logged on
activation.
