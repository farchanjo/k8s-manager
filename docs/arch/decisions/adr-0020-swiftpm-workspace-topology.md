# ADR-0020 — SwiftPM workspace topology

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — swiftpm, architecture, hexagonal, modules, build

## Context and problem statement

K8sManager is structured around a hexagonal architecture (ADR-0001, ADR-0005). The domain model for
each bounded context must be isolated from infrastructure concerns: it must not import HTTP clients,
cloud SDKs, SQLite libraries, YAML parsers, or any other framework that is specific to one delivery
mechanism. This isolation must be enforced mechanically, not just by convention.

In Swift 6 there are two tools that can enforce module boundaries at compile time: Swift package
targets and access control. If domain logic and infrastructure adapters are compiled into separate
SwiftPM targets, the compiler will reject any attempt by a domain target to import an infrastructure
library that is not declared as its dependency. This is stronger than code-review-level enforcement.

The problem is: how should the Package.swift manifest organise the library targets, their dependency
graph, their Swift language mode settings, and their test coverage such that:

- Domain core targets are provably free of infrastructure imports.
- Each bounded context can be compiled, tested, and reasoned about independently.
- The Xcode project generated from Package.swift is usable for daily development on macOS without a
  separate Xcode workspace configuration.
- The CI pipeline can run `swift build` and `swift test` without Xcode.
- All targets compile under Swift 6 strict concurrency with zero warnings.

## Decision drivers

- Compile-time enforcement of hexagonal layer boundaries. A domain target that accidentally imports
  GRDB, swiftkube/client, or soto must fail to compile, not just fail a linter check.
- Swift 6 strict concurrency for all targets without exception. This rules out mono-target designs
  where a single compilation unit cannot enforce boundary isolation.
- Independent testability: each domain core target must have a corresponding test target that can
  run without network, filesystem, or Keychain access. Adapters have separate test targets that may
  use test doubles for external services.
- CI-first design: `swift build` and `swift test` must work on a standard macOS CI runner without
  Xcode or special entitlements. The Xcode project is generated from Package.swift and is not the
  source of truth for the build graph.
- Readable and maintainable Package.swift: the manifest should be mechanical to extend when a new
  bounded context is added. Naming conventions must be consistent and self-documenting.

## Considered options

- Option A — SwiftPM multi-target workspace with one target per bounded context, separate adapter
  targets for each infrastructure concern, and a thin executable target for application wiring.
- Option B — Xcode workspace with multiple sub-projects (one per bounded context), using Xcode's
  scheme-level dependency management.
- Option C — Single monolithic target containing all domain logic and infrastructure code, relying
  on Swift access control and code review to enforce boundaries.

## Decision outcome

Chosen option: Option A — SwiftPM multi-target workspace.

Option B is rejected because Xcode workspace configuration is not expressed as code, is difficult to
review in pull requests, is fragile under merge conflicts in `.xcodeproj` XML, and requires Xcode to
build. The CI pipeline must not require Xcode; `swift build` on a headless runner must produce the
full application binary.

Option C is rejected because it cannot provide compile-time enforcement of hexagonal boundaries. A
single target allows any file to import any framework regardless of layer. Experience on similar
projects shows that layer violations in a mono-target accumulate rapidly without mechanical
enforcement, and are expensive to refactor later.

### Consequences

Positive consequences:

- Compiler enforces layer boundaries: if a developer adds `import GRDB` to a domain core source
  file, the build fails immediately because GRDB is not in that target's dependencies.
- Each bounded context can be unit-tested in isolation with pointfreeco/swift-dependencies overrides
  for all adapter ports. No network, no Keychain, no SQLite required in domain core tests.
- `swift package show-dependencies` produces a verifiable acyclic graph. The confirmation check runs
  in CI on every pull request.
- Adding a new bounded context requires only: one new domain core target, one or more new adapter
  targets, one new test target, and entries in `K8sManagerApp` dependencies. The pattern is
  mechanical.

Negative consequences:

- Package.swift becomes large (approximately 500 to 700 lines) as the number of targets grows. This
  is accepted as a maintenance trade-off; the manifest is generated from a template pattern and is
  not hand-crafted per target.
- SwiftPM does not support conditional compilation flags at the target level as flexibly as Xcode
  build settings. Feature flags must be managed via Swift compiler conditions set in Package.swift.
- Xcode's generated project from Package.swift does not preserve custom schemes or test plans. Those
  must be declared in the Package.swift test target configurations or maintained separately as
  `.xctestplan` files committed to the repository.
- The large number of targets (26 library targets plus test targets plus one executable) increases
  clean build time. Incremental builds are fast because SwiftPM only recompiles targets whose
  sources or dependencies changed.

### Confirmation

The following checks must pass after Package.swift is committed:

- `swift package show-dependencies --format json` produces an acyclic dependency graph. No domain
  core target (`ClusterConnectivity`, `ContextNavigation`, `LLMProvider`, `AssistantChat`,
  `ClusterIntelligence`, `LocalPersistence`, `ResourceBrowser`, `PortForwarding`, `HelmManagement`,
  `MetricsObservability`, `TerminalSession`) lists `swiftkube-client`, `GRDB`, `Yams`,
  `AsyncHTTPClient`, `soto`, `MSAL`, `AppAuth`, `SwiftAnthropic`, or `OpenAI` as a transitive
  dependency.
- `swift build -c release` succeeds without warnings for all targets compiled with
  `-strict-concurrency=complete` and `-language-mode 6`.
- `swift test --filter <BoundedContextModule>Tests` runs each domain core test suite to completion
  without requiring network connectivity or Keychain access. Test doubles registered via
  swift-dependencies cover all port interactions.
- A newly added bounded context (domain core + adapter + tests) that inadvertently adds
  `import GRDB` to the domain core source produces a build error, not a runtime error or lint
  warning.

## Pros and cons of the options

### Option A — SwiftPM multi-target workspace (chosen)

Positive:

- Compile-time hexagonal boundary enforcement at zero runtime cost.
- CI builds via `swift build` and `swift test` without Xcode.
- Package.swift is version-controlled, diff-friendly, and merge-conflict recoverable.
- Incremental compilation is efficient: SwiftPM tracks target-level change fingerprints.
- Consistent naming conventions make the module topology self-documenting.

Negative:

- Package.swift grows large as bounded contexts accumulate; requires discipline to keep the manifest
  readable.
- SwiftPM has less flexible build-setting expressiveness than Xcode build phases for code-signing
  and entitlements; those concerns stay in the Xcode project that wraps the package for distribution
  builds.

### Option B — Xcode workspace with sub-projects

Positive:

- Familiar to developers with Xcode experience.
- Xcode provides richer build setting UI for code signing and entitlements.

Negative:

- Xcode project files are XML blobs that are difficult to review in pull requests and prone to merge
  conflicts.
- Cannot build from CI without Xcode installed; rules out Linux or headless macOS runners without
  full Xcode.
- Dependency graph between sub-projects is not expressed as code and cannot be verified
  mechanically.
- Xcode workspace format is proprietary; incompatible with SwiftPM toolchain standalone.

### Option C — Single monolithic target

Positive:

- Simplest Package.swift: one library target, one test target.
- Lowest clean build overhead: one compilation unit.

Negative:

- No compile-time hexagonal boundary enforcement. Layer violations are only caught by code review.
- Cannot test domain logic without importing infrastructure (GRDB, soto, etc.), making tests slow
  and fragile.
- Not scalable: as the codebase grows, the single target becomes a compilation bottleneck because
  all source files recompile on any change.
- Contradicts the architectural commitments in ADR-0001 and ADR-0005.

## More information

### Domain core targets

`SharedKernel` is a library target depended on by every other target. It declares only Sendable
value types: `ClusterId`, `ContextId`, `KubeconfigPath`, a `UUIDv7` generator backed by Foundation
UUID with time-ordering, and an `RFC3339Clock` protocol with a `SystemClock` implementation.
`SharedKernel` has zero external dependencies beyond Foundation.

Each bounded context maps to one domain core library target:

- `ClusterConnectivity` — cluster registration, health probe, exec credential port, TLS trust policy
  port.
- `ContextNavigation` — kubeconfig context enumeration, active context switching, namespace
  selection.
- `LLMProvider` — LLM provider registration, model listing, streaming completion port, key store
  port.
- `AssistantChat` — conversation session management, message history, tool call/result pair
  recording.
- `ClusterIntelligence` — cluster-aware prompt enrichment, resource context injection, the
  in-process MCP server domain model (see ADR-0009).
- `LocalPersistence` — ports for chat repository, provider repository, and cluster metadata store.
  No GRDB import; only protocol declarations and domain value types.
- `ResourceBrowser` — Kubernetes resource list, detail, and event stream ports. Pagination cursor
  value types.
- `PortForwarding` — port-forward session lifecycle, forwarding rule value types, channel status
  port.
- `HelmManagement` — Helm release value types, chart metadata, diff result types, release lifecycle
  port.
- `MetricsObservability` — metric query port, time series value types, alert rule value types.
- `TerminalSession` — PTY session lifecycle, input/output stream port, session state value type.

`AppShell` is a library target containing SwiftUI views and view-models. It depends on the
read-model value types from domain core targets but must not depend on adapter targets. View-models
call domain ports through pointfreeco/swift-dependencies injection. `AppShell` must not import GRDB,
swiftkube/client, or any adapter library directly.

`K8sManagerApp` is the single executable target. It imports all adapter targets and all domain core
targets and performs the wiring: registering concrete adapter implementations against the port keys
declared by pointfreeco/swift-dependencies. No business logic lives in `K8sManagerApp`; it is
exclusively a composition root.

### Adapter targets

Each adapter target imports exactly one infrastructure library and the domain core target whose port
it implements. An adapter target must not import a second infrastructure library (e.g.,
`SwiftkubeClientAdapter` must not import GRDB). Cross-infrastructure concerns (e.g., a Prometheus
query result that is also persisted) are mediated through the domain core layer using domain events
or read models, never through direct adapter-to- adapter imports.

The complete adapter target list is:

- `SwiftkubeClientAdapter` — imports swiftkube/client and async-http-client; implements
  `KubernetesApiPort`, `WatchPort`, and the custom `ServerSideApplyClient`.
- `YamsKubeconfigAdapter` — imports Yams; implements `KubeconfigLoaderPort`.
- `KeychainAdapter` — imports Security framework; implements `LLMKeyStorePort`.
- `GRDBPersistenceAdapter` — imports GRDB; implements `ChatRepositoryPort`,
  `ProviderRepositoryPort`, and `ClusterMetadataStorePort`.
- `AnthropicAdapter` — imports SwiftAnthropic; implements `LLMStreamingPort` for Anthropic Claude
  models.
- `OpenAIAdapter` — imports MacPaw/OpenAI with OpenAI production baseURL; implements
  `LLMStreamingPort` for GPT models.
- `OpenAICompatibleAdapter` — imports MacPaw/OpenAI with configurable baseURL and host; implements
  `LLMStreamingPort` for Ollama, LM Studio, vLLM, and any OpenAI-compatible endpoint.
- `MCPSwiftSDKAdapter` — imports modelcontextprotocol/swift-sdk; implements the in-process MCP
  transport for `ClusterIntelligence`.
- `AWSExecCredentialAdapter` — imports soto; implements `ExecCredentialPort` for AWS EKS IAM
  authenticator protocol.
- `GCPExecCredentialAdapter` — imports apple/swift-crypto (CryptoExtras) and vapor/jwt-kit;
  implements `ExecCredentialPort` for GCP ADC. No external GCP library (archived).
- `AzureExecCredentialAdapter` — imports MSAL; implements `ExecCredentialPort` for Azure Entra ID.
- `OIDCExecCredentialAdapter` — imports AppAuth and vapor/jwt-kit; implements `ExecCredentialPort`
  for generic OIDC providers.
- `SubprocessExecCredentialAdapter` — imports Foundation Process; the subprocess fallback for
  unrecognised exec plugin names (ADR-0018).
- `PrometheusQueryAdapter` — imports async-http-client; implements the custom Prometheus HTTP API
  query client (~340 LoC).
- `WebSocketExecAdapter` — uses Foundation URLSessionWebSocketTask; implements pods/exec channel
  framing (v5.channel.k8s.io).
- `WebSocketPortForwardAdapter` — uses Foundation URLSessionWebSocketTask; implements
  pods/portforward protocol (portforward.k8s.io).

### Build configuration in Package.swift

The Package.swift manifest declares:

- `swift-tools-version: 6.1` at the top of the file. This is the minimum toolchain version required
  to build the package.
- `.package(url: ..., exact: "x.y.z")` version pins for all external dependencies. Exact pins are
  used (not ranges) to eliminate non-reproducible builds. Upgrades are performed explicitly and
  recorded in a dependency upgrade ADR addendum when they cross a major version.
- `swiftLanguageVersions: [.v6]` on the package declaration.
- `platforms: [.macOS(.v14)]` on the package declaration.
- Each target declaration includes:
  - `swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]` for targets that must be Swift 6
    language mode clean.
  - `swiftSettings: [.unsafeFlags(["-language-mode", "6"])]` for targets in the migration period
    before `.swiftLanguageVersion(.v6)` setting stabilises in the toolchain version in use.
- The `K8sManagerApp` executable target includes linker settings for the Hardened Runtime but does
  not set entitlements directly; entitlements are managed in the Xcode project that wraps the
  package for release builds. The SwiftPM-only build (used in CI for lint and test) does not require
  entitlements.
- Test targets use the `.testTarget` product and depend on pointfreeco/swift-concurrency-extras for
  actor isolation test helpers. Test targets must not depend on any adapter library except their
  designated adapter under test.

### Dependency graph invariants

The following edges must never appear in the resolved dependency graph. Violations cause a CI
failure via the `swift package show-dependencies` verification step.

- Any domain core target (`ClusterConnectivity`, `ContextNavigation`, `LLMProvider`,
  `AssistantChat`, `ClusterIntelligence`, `LocalPersistence`, `ResourceBrowser`, `PortForwarding`,
  `HelmManagement`, `MetricsObservability`, `TerminalSession`) must not depend on
  `swiftkube-client`, `GRDB`, `Yams`, `AsyncHTTPClient`, `soto`, `MSAL`, `AppAuth`,
  `SwiftAnthropic`, `OpenAI`, `swift-crypto` (directly or transitively).
- `AppShell` must not depend on any adapter target.
- Adapter targets must not depend on each other. Cross-adapter collaboration is mediated by the
  domain core layer.
- `SharedKernel` must have zero external dependencies.

These invariants are checked in CI by parsing the JSON output of `swift package show-dependencies`
and asserting that the transitive dependency sets of the listed targets do not contain the listed
libraries. A small Python script (`scripts/check-dependency-invariants.py`) performs this check and
fails the build with a human-readable error message identifying the violating edge.
