# Performance Measurement

This document describes the methodology, tooling, and CI assertion strategy used to verify that
K8sManager meets the performance budgets defined in
`docs/arch/contexts/_shared/schemas/performance_budgets.cue` and the Rego policy
`docs/arch/contexts/_shared/policies/performance_invariants.rego`.

All ceilings are invariants. A release that does not pass every assertion below is a broken release
regardless of other quality signals.

## Measurement methodology

Every release pipeline executes an Instruments trace session driven by the template file
`K8sManager.tracetemplate` (committed to the `Instruments/` directory at the repository root; not
reproduced here). The template activates the following Instruments subsystems simultaneously:

- **CPU Profiler** — records per-thread CPU usage at 1 ms sample rate.
- **Allocations** — records heap allocations per category; filtered to `ClusterSession` and
  `EditorSession` allocation tags.
- **Leaks** — detects orphaned allocations across session boundaries.
- **Activity Monitor** — records process-level RSS at 500 ms intervals.
- **File Activity** — records open file descriptor counts per process.
- **kqueue Events** (custom signpost instrument) — records events/s from the self-monitoring surface
  as defined in ADR-0027.
- **Network** — records bytes in/out per connection; used to validate the port-forward bandwidth
  ceiling.

The trace is recorded on a reference machine (Apple M-series, macOS 14+) in a reproducible
environment: fresh app launch, Kind cluster provisioned with the CI seed script
(`scripts/ci/kind-seed.sh`), and no other user processes competing for CPU.

## Per-frame trace points

The Swift implementation MUST wrap each SwiftUI rendering pass with signpost events using the
`OSSignposter` API:

```
let signposter = OSSignposter(subsystem: "app.k8smanager", category: "render")
let state = signposter.beginInterval("renderFrame")
// ... SwiftUI body evaluation ...
signposter.endInterval("renderFrame", state)
```

These signpost intervals are captured by the Instruments template and aggregated into a latency
distribution. The 99th percentile of `renderFrame` intervals MUST be at or below 16 ms. The mean and
median are informational; only p99 is a pass/fail gate.

## CI budget assertions

The following steps run as a dedicated Xcode scheme (`PerformanceBudgets`) in CI on every pull
request that modifies any file under:

- `Sources/` (any Swift target)
- `docs/arch/contexts/_shared/schemas/performance_budgets.cue`
- `docs/arch/contexts/_shared/policies/performance_invariants.rego`
- `docs/arch/decisions/adr-0024-*.md`
- `docs/arch/decisions/adr-0035-*.md`

### Kind cluster setup

```
kind create cluster --config scripts/ci/kind-config.yaml
kubectl apply -f scripts/ci/seed-100-pods.yaml
kubectl wait --for=condition=Ready pod --all --timeout=120s
```

The seed manifest (`seed-100-pods.yaml`) creates 100 Pods distributed across 5 namespaces with
resource requests set to 10m CPU / 32Mi memory each. The cluster represents a realistic small-team
workload.

### Frame render assertion

```
xcodebuild test \
  -scheme PerformanceBudgets \
  -testPlan FrameRenderBudget \
  -destination "platform=macOS"
```

The test plan opens the resource browser against the Kind cluster, scrolls through the full Pod list
(100 items), and renders 30 frames while the watch stream delivers live updates. XCTest
`measure(metrics:)` records per-frame wall-clock durations. The assertion:

```swift
measure(metrics: [XCTClockMetric()]) {
    // render 30 frames with live watch events
}
// recorded values available via XCTPerformanceMetric
```

The test fails if the p99 frame duration exceeds 16 ms. The XCTest result bundle records the full
distribution for trend analysis.

### Memory ceiling assertions

XCTest `measure` blocks validate all ceilings from
`docs/arch/contexts/_shared/schemas/performance_budgets.cue`:

**Baseline RSS (idle, 1 cluster).** The test launches the app, connects to the Kind cluster, waits
10 seconds for steady state, then samples RSS via the self-monitoring API (`/diagnostics/metrics`).
The assertion fails if `rssMB > 200`.

**Loaded RSS (3 clusters, 5 watches each, dashboard open).** The test connects 3 Kind clusters
(provisioned by the CI matrix), opens 5 watch subscriptions per cluster, opens the ClusterOverview
dashboard, and waits 30 seconds for steady state. The assertion fails if `rssMB > 600`.

**Per-ClusterSession memory.** The test creates one `ClusterSessionActor` in isolation, measures
heap allocation via `XCTMemoryMetric`, and asserts that the allocation does not exceed 10 MB. The
test runs without a real cluster; a mock `KubernetesApiPort` is injected.

**Per-EditorSession memory.** The test creates one `EditorSession` with a 500 KB YAML manifest,
saves a draft, and asserts that the combined allocation does not exceed 1 MB.

### Dashboard query budget assertion

The test constructs a synthetic `ClusterOverview` dashboard with 11 widgets (the maximum widget
count for that scope as defined by the scope preset). A mock `MetricsQueryPort` records each
distinct query dispatch. After one full refresh cycle the test asserts:

```swift
XCTAssertLessThanOrEqual(mockPort.recordedQueryCount, 5,
    "ClusterOverview refresh must issue at most 5 Prometheus queries")
```

A count of 6 or more fails CI and blocks merge.

## References

- ADR-0027 — App Self-Monitoring: self-monitoring API surface and signpost integration that provides
  the `rssMB`, `kqueueEventsPerSecond`, and `frameTimeMs` metrics consumed by the Rego policy.
- ADR-0034 — State-Driven Realtime UI Architecture: `@Observable` read model contract that the frame
  render assertion validates end-to-end.
- ADR-0035 — Reactive Stack Integration: backpressure invariants and memory ceilings that the XCTest
  measure blocks enforce.
- `docs/arch/contexts/_shared/schemas/performance_budgets.cue` — canonical numeric ceilings
  referenced by all assertions above.
- `docs/arch/contexts/_shared/policies/performance_invariants.rego` — Rego policy that validates
  MetricsSample envelopes against the same ceilings.
