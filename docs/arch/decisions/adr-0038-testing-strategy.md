# ADR-0038 — Testing strategy

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0008 (LLM provider abstraction — port conformance suites promised there are
  formalised here), ADR-0010 (local persistence — in-memory test database strategy), ADR-0011 (Swift
  concurrency conventions), ADR-0019 (adopted Swift libraries — `pointfreeco/swift-dependencies` and
  `pointfreeco/swift-snapshot-testing`)
- Tags — testing, quality, ci, coverage, tdd, snapshot, contract, property-based, k8s, kind

## Context and problem statement

K8sManager is built on a hexagonal architecture (ports and adapters). ADR-0008 promised conformance
suites that every adapter for a given port must pass. ADR-0010 uses GRDB SQLite for persistence.
ADR-0011 establishes Swift Concurrency as the execution model, which requires async-aware test
patterns. ADR-0019 adopts `pointfreeco/swift-dependencies` for dependency injection and
`pointfreeco/swift-snapshot-testing` for SwiftUI snapshots.

No document formalises the full testing taxonomy, the isolation strategy for Keychain and SQLite in
tests, property-based testing conventions, K8s integration test setup, or coverage targets per
layer. Without a unified strategy, test suites are inconsistent and CI pipelines cannot enforce
coverage gates.

## Decision drivers

- Hexagonal architecture requires that ports, not adapters, are the primary test surface: every
  adapter must pass the same parameterised conformance suite.
- GRDB SQLite must be exercised in-memory so tests are fast and leave no filesystem state.
- Keychain access in tests must be isolated by service prefix and cleaned up deterministically.
- SwiftUI views must be snapshot-tested to catch unintended layout regressions.
- K8s integration tests must run against a real cluster (provided by `kind` in CI) to verify TLS,
  watch stream semantics, and server-side apply behaviour.
- Coverage targets must be enforced automatically in the PR pipeline.

## Considered options

### Option A — No formal taxonomy; each module decides independently

Each module author writes tests in whatever style they prefer. No conformance suites, no coverage
gates, no shared fixture patterns.

Pros:

- Zero coordination overhead.

Cons:

- Adapter correctness is not verified against port contracts.
- Coverage is uneven and unknown at the project level.
- Test isolation varies; flaky tests are common.

### Option B — Unified testing strategy documented in this ADR (chosen)

A taxonomy of five test categories is defined. Conformance suites, isolation patterns, snapshot
conventions, K8s integration setup, and coverage targets are all prescribed here and enforced by
`scripts/test.sh` in CI.

Pros:

- Port correctness is mechanically verified for every adapter.
- Coverage gates prevent regression.
- Consistent patterns make test code predictable and reviewable.

Cons:

- Upfront documentation and infrastructure cost.
- Conformance suites must be updated when a port interface changes.

## Decision outcome

Adopt Option B.

## Test taxonomy

The test suite is divided into five categories. Each category has a distinct scope, fixture
strategy, and coverage expectation.

### Unit tests

Scope: a single domain type, use case, or port-isolated component. No network, no real database, no
real Keychain, no real K8s cluster.

Fixture strategy: all ports are overridden via `@Dependency` test values from
`pointfreeco/swift-dependencies`. Each port declares three values:

- `liveValue` — the production adapter (registered in the main app target).
- `testValue` — a lightweight test double that returns controlled results.
- `previewValue` — a preview-friendly double with predictable canned data.

Test doubles for async ports return `AsyncStream` sequences constructed from arrays of pre-loaded
values. Test doubles for throwing ports return configurable `Result` values.

Coverage target: domain core (use cases, domain services, value objects, aggregate roots) >= 90%.

### Integration tests

Scope: a single adapter exercised against a real external resource that is controllable and fast:
GRDB SQLite in-memory database or a real Keychain entry in a test-scoped namespace.

Test database strategy: every integration test that touches persistence creates a new GRDB database
via `DatabaseQueue(configuration:)` with a `:memory:` path. The database is schema-migrated at test
setup using the production `AppDatabaseMigrator` and torn down by the `DatabaseQueue` deallocation.
No filesystem state remains after the test.

Keychain isolation: tests that touch Keychain use the service prefix
`com.archanjo.K8sManager.test.<uuid>` where `<uuid>` is generated fresh per test suite run. A
`tearDown` method calls `SecItemDelete(query as CFDictionary)` for every item written under the
prefix. No test Keychain entries survive a test run.

Coverage target: adapters (persistence, credential, kubeconfig, Prometheus query) >= 80%.

### Contract tests (port conformance suites)

Scope: every concrete adapter for a given port. The same parameterised `XCTestCase` subclass runs
against each adapter implementation.

Structure: a base `ConformanceSuite<Port>` class (or `protocol`-constrained `@Suite` in
swift-testing) declares all required test methods against an abstract subject. Each adapter test
target subclasses the suite and supplies the concrete adapter as the subject.

Example for `KubernetesApiPort`:

```
KubernetesApiPortConformance (base suite)
├── SwiftkubeClientAdapterConformanceTests  (live adapter, kind cluster)
└── FakeKubernetesApiAdapterConformanceTests (test double, in-process)
```

Every method in a port protocol MUST have at least one test case in the conformance suite. Methods
with error paths (timeout, not-found, server-side-apply conflict) MUST have dedicated error-path
test cases.

Coverage target: every port method covered by at least one conformance test. This is a structural
requirement, not a percentage.

### UI tests

Scope: SwiftUI views and view models. Two sub-categories:

Snapshot tests: use `pointfreeco/swift-snapshot-testing` with the
`.image(layout: .device(config: .macBookPro))` strategy for all popover and main window views.
Snapshots are committed to the repository and compared in CI. A failing snapshot is treated as a
regression; the contributor must update the snapshot intentionally with `record: true` and include
it in the PR.

Interaction tests: use `XCUIApplication` for critical user flows: cluster switch, port-forward
start/stop, context palette invocation. Interaction tests run against the macOS 14 simulator in CI.

Coverage target: UI surfaces (views and view models) >= 60% line coverage; 100% of MVP++ flows
covered by at least one snapshot or interaction test.

### End-to-end tests

Scope: full application flows against a real `kind` Kubernetes cluster. These tests verify that the
complete stack — from SwiftUI action to Kubernetes API response — functions correctly.

K8s cluster setup in CI:

```bash
# scripts/ci/setup-kind.sh
kind create cluster --name k8smanager-test --config kind-config.yaml
kubectl --context kind-k8smanager-test apply -f test/fixtures/namespaces.yaml
kubectl --context kind-k8smanager-test apply -f test/fixtures/deployments.yaml
```

Per-cluster TLS overlays: the test harness generates a self-signed CA and cluster certificate using
`apple/swift-certificates` (or the `openssl` CLI in CI) and registers the CA in the test kubeconfig.
This exercises the custom CA code path in `SwiftkubeClientAdapter`.

Coverage target: 100% of MVP++ operator flows have at least one end-to-end test case. MVP++ flows
are enumerated in the acceptance criteria column of the project issue tracker.

## Property-based testing

`swift-testing` is used for property-based (fuzz-style) tests on parsing and validation logic. Test
cases use `@Test(arguments:)` with synthesised input arrays covering:

- Kubeconfig YAML parsing: valid kubeconfigs, malformed YAML, missing required fields, duplicate
  context names, oversized bearer tokens.
- YAML diff (resource diff viewer): identical documents, single-field change, nested map change,
  array reorder.
- Mutation policy evaluation: all combinations of allowed verbs × resource kinds × namespace match
  patterns (ADR-0012).

For true randomised fuzzing, the `swift-testing` `randomized` trait (if available in the adopted
swift-testing version) or a custom `Arbitrary`-protocol approach supplies random inputs. The fuzzing
budget is capped at 1 000 iterations per property in CI to keep suite duration bounded.

## CI script contract

`scripts/test.sh` accepts a `--suite` flag:

```
scripts/test.sh --suite unit
scripts/test.sh --suite integration
scripts/test.sh --suite contract
scripts/test.sh --suite ui
scripts/test.sh --suite e2e
```

Running without `--suite` executes unit + integration + contract (the fast path, under 5 minutes).
The `ui` and `e2e` suites run in dedicated CI jobs to avoid blocking fast feedback on pull requests.

Coverage reports are generated via `xcov` or `swift test --enable-code-coverage` with
`llvm-cov export`. The PR pipeline fails if any coverage target (domain core < 90%, adapters < 80%,
UI surfaces < 60%) is not met.

### Consequences

**Positive**

- Port correctness is enforced mechanically through conformance suites.
- In-memory GRDB and Keychain prefix isolation guarantee no test cross-contamination.
- Snapshot tests catch unintended SwiftUI layout regressions automatically.
- `kind`-based end-to-end tests verify the full stack without requiring a real cloud cluster.
- Coverage gates prevent silent regressions as the codebase grows.

**Negative**

- Conformance suites must be kept in sync with port interfaces. A new method on a port requires a
  new test case in every conformance suite that covers that port.
- Snapshot tests produce binary diff noise when macOS rendering changes across Xcode versions;
  intentional snapshot updates require a deliberate PR step.
- `kind` cluster setup adds 60–90 seconds to CI job startup.

**Neutral**

- The `previewValue` adapter pattern benefits Xcode Canvas previews at no test-infrastructure cost;
  it is a free side-effect of the dependency injection discipline.

### Confirmation

- `scripts/test.sh --suite unit` completes in under 60 seconds on a developer machine and exits 0.
- `scripts/test.sh --suite integration` completes in under 3 minutes and exits 0, with no filesystem
  artefacts remaining after the run (verified by
  `find /tmp -name "*.sqlite" -newer before-timestamp` returning empty).
- `scripts/test.sh --suite contract` runs all conformance suites and exits 0. A port method with no
  conformance test causes the suite to exit non-zero.
- `scripts/test.sh --suite ui` generates snapshot images in `Tests/Snapshots/__Snapshots__/` and
  exits 0. A visual regression exits 1 with a diff image path in the output.
- `scripts/test.sh --suite e2e` requires `kind` in `$PATH` and a functioning Docker daemon; it exits
  0 after completing all MVP++ flow test cases.
- Coverage report from a full local run (`--suite unit integration contract`) shows domain core >=
  90%, adapters >= 80%, UI surfaces >= 60%.

## More information

- ADR-0008 — LLM provider abstraction (conformance suites promised for every port adapter;
  formalised by this ADR).
- ADR-0010 — Local persistence (GRDB `:memory:` path and migration strategy used in integration
  tests).
- ADR-0011 — Swift concurrency conventions (async test patterns; `withCheckedThrowingContinuation`
  and `AsyncStream` test fixtures).
- ADR-0019 — Adopted Swift libraries (`pointfreeco/swift-dependencies`,
  `pointfreeco/swift-snapshot-testing`, `pointfreeco/swift-concurrency-extras`).
- ADR-0037 — Concurrency lifecycle invariants (confirmation tests for cancellation propagation,
  reentrancy, and deadlock prevention are part of the unit and integration suites defined here).
