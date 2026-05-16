# ADR-0058 — Embedded Prometheus charts in resource detail drawer

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0016 (Prometheus integration), ADR-0044 (PromQL injection prevention),
  ADR-0051 (multi-cluster workspace)
- Tags — prometheus, charts, detail-drawer, metrics-observability, sparkline

## Context and problem statement

ADR-0051 specifies that the resource detail drawer (section "Detail drawer") contains a metrics
panel for Prometheus CPU/memory sparklines for Pods, Nodes, and Deployments. ADR-0016 defines the
Prometheus HTTP client, curated PromQL templates, caching, and the graceful degradation path when
Prometheus is not present. Neither ADR specifies the concrete SwiftUI contracts for the chart
components embedded in the drawer, the time-range and series picker controls, the PromQL templates
for multi-series charts (Usage / Requests / Allocatable / Capacity), the refresh cadence ceiling to
bound Prometheus QPS when multiple drawers are open, or the click-through behaviour that connects
the compact drawer chart to the full metrics dashboard.

The reference recording (`Screen Recording 2026-05-16 at 13.19.58.mov`, R30 in the feature-gap
analysis) shows a Node detail drawer with a live CPU chart rendering four named series — Usage,
Requests, Allocatable, and Capacity — over a 50-minute window, with X-axis tick marks, a hover
tooltip displaying each series value at the cursor position, and a time-range selector. The chart
is compact (single-column, inline in the drawer scroll view) rather than full-height dashboard. A
click-through affordance opens the full metrics tab for deeper analysis.

This ADR must settle:

- Which SwiftUI component hierarchy renders the drawer chart and what its data-source binding is.
- What PromQL templates feed each series for each supported resource kind (Node, Pod, Deployment,
  StatefulSet, DaemonSet).
- What the refresh cadence ceiling is per drawer.
- What the time-range and series picker contracts are.
- How the component downsizes gracefully when Prometheus is not configured.
- How click-through from the compact drawer chart reaches the full metrics dashboard tab.

## Decision drivers

- **Operator situational awareness** — an operator looking at a Node in the detail drawer must
  immediately see CPU and memory trend without navigating to a separate view.
- **Refresh-cadence ceiling** — multiple drawers open simultaneously against the same Prometheus
  endpoint must not saturate QPS. A hard ceiling of one query per metric per 15 seconds per
  open drawer prevents runaway polling.
- **Graceful fallback** — when Prometheus is not configured for the cluster, the metrics panel
  hides the chart and shows an actionable hint directing the operator to Settings > Metrics. No
  blank space or unhandled error must be shown.
- **Reuse of existing query infrastructure** — the chart must bind to `MetricsObservabilityActor`
  rather than issuing direct HTTP calls, to benefit from the 5-second in-memory cache and the
  injection guard from ADR-0044.
- **Compact rendering** — the drawer has a fixed width (280–600 pt). The chart must be
  sparkline-style and legible within that constraint. It must not clone the full-height dashboard
  layout.
- **Click-through to full dashboard** — the compact chart must be an entry point to the full
  metrics tab, not a terminal view.

## Considered options

### Option A — Dedicated MetricsObservabilityView tab only

The full metrics dashboard (already designed as a first-class tab) is the only place CPU/memory
trend charts appear. The detail drawer shows only instantaneous readings (no chart).

Rejected. Operators must navigate away from the resource list to see trend data, breaking the
situational awareness requirement. The reference recording (R30) explicitly shows a chart inside
the drawer.

### Option B — Chart embedded in detail drawer with sparkline-style compact rendering

A compact `MetricSparkline` component renders inside the drawer metrics panel. It shows a single
series (default: CPU usage) as a thin line chart. No time-range picker. No series picker.

Rejected in its pure form. Single-series rendering matches the sparkline pattern but is
insufficient for Node context where operators need to compare usage against requests, allocatable,
and capacity simultaneously. It also provides no path to detailed analysis.

### Option C — Drawer chart with click-through to full dashboard (chosen)

A compact `MetricChart` component with a time-range picker and a series picker renders inside the
drawer metrics panel. It shows up to four named series. A "View in Metrics" button opens the full
metrics tab for the resource. The component delegates all query dispatch to `MetricsObservabilityActor`.

This option provides the situational awareness of Option B while adding multi-series context and
a click-through path to deeper analysis. It matches the reference recording behaviour exactly.

## Decision outcome

Chosen option — **Option C**, because:

- Multi-series display (Usage / Requests / Allocatable / Capacity) gives operators the capacity
  context needed to diagnose pressure without navigating away.
- The click-through to the full metrics tab preserves the compact drawer footprint while providing
  an escape hatch for deeper analysis.
- Delegating all queries to `MetricsObservabilityActor` ensures the refresh ceiling, caching, and
  injection guard from ADR-0016 and ADR-0044 apply without duplication.

### MetricSparkline and MetricChart SwiftUI component contracts

#### MetricSparkline

`MetricSparkline` is a lightweight inline chart used where only a single-series trend is needed
(e.g., CPU trend in a list row or status bar tooltip). It is not the primary chart in the drawer
but may appear in summary rows.

Signature:

```swift
struct MetricSparkline: View {
    let series: MetricSeries
    var height: CGFloat = 36
    var strokeColor: Color = .accentBrand
}
```

Data source: a `MetricSeries` value type passed from the view model. The view model subscribes
to `MetricsObservabilityActor` and publishes the latest downsampled series.

#### MetricChart

`MetricChart` is the primary chart component embedded in the detail drawer metrics panel.

Signature:

```swift
struct MetricChart: View {
    @Binding var timeRange: MetricTimeRange
    @Binding var selectedSeries: Set<MetricSeriesKey>
    let resource: KubernetesResourceRef
    @StateObject var viewModel: MetricChartViewModel
}
```

`MetricTimeRange` is an enum with cases: `.fiveMinutes`, `.fifteenMinutes`, `.oneHour`,
`.threeHours`, `.twentyFourHours`. The picker renders as a segmented control labelled
`5m / 15m / 1h / 3h / 24h` directly above the chart.

`MetricSeriesKey` identifies a named series and maps to a curated PromQL template. The series
picker renders as a multi-select chip row below the time-range picker. Default selection for
Node: all four series. Default selection for Pod and workload kinds: CPU Usage + Memory Usage.

`MetricChartViewModel` subscribes to `MetricsObservabilityActor` and requests range queries on
time-range or series changes. It publishes `[MetricSeriesKey: MetricSeries]` to the view.

The chart renders a `Chart` (Swift Charts framework) with `LineMark` per active series, `PointMark`
for hover tooltip, and a horizontal rule at the y-axis maximum for the Capacity series (Node only).
X-axis shows time ticks; y-axis shows values in the appropriate unit (millicores for CPU, mebibytes
for memory). A "View in Metrics" button appears below the chart and opens the full metrics tab for
the current resource kind.

#### Downsampling

`MetricChartViewModel` applies the ADR-0016 downsampling rule (uniform index sampling to 200 points
maximum) before publishing to the view. The view itself is a pure read of the published value.

### PromQL templates per kind

All templates use the curated template mechanism from ADR-0016. Placeholder substitution is
validated via the ADR-0044 whitelist regex before any query is issued.

#### Node

- CPU Usage: `rate(node_cpu_usage_seconds_total{node=~"^{node}$",mode!="idle"}[2m])`
- CPU Requests: derived from `kube_pod_container_resource_requests{resource="cpu",node=~"^{node}$"}`
  summed across all pods on the node.
- CPU Allocatable: `kube_node_status_allocatable_cpu_cores{node=~"^{node}$"}`
- CPU Capacity: `kube_node_status_capacity_cpu_cores{node=~"^{node}$"}`

Memory series follow the same four-series shape using `node_memory_MemTotal_bytes`,
`node_memory_MemAvailable_bytes`, `kube_node_status_allocatable_memory_bytes`, and
`kube_node_status_capacity_memory_bytes`.

#### Pod

- CPU Usage: `rate(container_cpu_usage_seconds_total{namespace=~"^{namespace}$",pod=~"^{pod}$",container!=""}[2m])`
- CPU Requests: `kube_pod_container_resource_requests{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="cpu"}`
- CPU Limits: `kube_pod_container_resource_limits{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="cpu"}`
- Memory Usage: `container_memory_working_set_bytes{namespace=~"^{namespace}$",pod=~"^{pod}$",container!=""}`
- Memory Requests: `kube_pod_container_resource_requests{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="memory"}`
- Memory Limits: `kube_pod_container_resource_limits{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="memory"}`

Default series selection for Pod: CPU Usage + Memory Usage (two series). Additional series
available via the series picker.

#### Deployment, StatefulSet, DaemonSet

Aggregate metrics are computed across all pods controlled by the workload.

- CPU Usage (aggregate): `sum(rate(container_cpu_usage_seconds_total{namespace=~"^{namespace}$"}[2m])) by (pod)` filtered to pods matching the owner reference label `{workload}`.
- Replicas Overlay: `kube_deployment_status_replicas_available{namespace=~"^{namespace}$",deployment=~"^{workload}$"}` (Deployment); `kube_statefulset_status_replicas_ready` (StatefulSet); `kube_daemonset_status_number_ready` (DaemonSet).

The replicas overlay is rendered as a secondary Y-axis (right side, integer scale) so it does not
distort the CPU/memory scale on the primary axis.

### Refresh cadence ceiling

`MetricChartViewModel` enforces a hard ceiling of one query per `(endpointId, queryId)` pair per
15 seconds while the drawer is open. The ceiling is implemented as a per-key timestamp dictionary
inside `MetricsObservabilityActor`. A query request that arrives within 15 seconds of the last
completed request for the same key returns the cached result from the ADR-0016 5-second in-memory
cache if available, or waits until the 15-second window elapses.

When the drawer is closed, `MetricChartViewModel` cancels all in-flight query tasks and clears its
subscriptions to `MetricsObservabilityActor`. This prevents phantom queries from a closed drawer
from continuing to consume Prometheus QPS.

### No-Prometheus fallback

When `MetricsObservabilityActor` reports that no Prometheus endpoint is configured for the active
cluster (`PrometheusEndpointStatus == .notConfigured`), the metrics panel in the detail drawer
replaces the chart with a static hint view:

> Configure Prometheus (Settings > Metrics) to see charts here.

The hint includes a button labelled "Open Settings" that navigates to Settings > Metrics directly.
No blank space, no loading spinner, and no unhandled error is shown. The chart component is not
instantiated when the endpoint status is `.notConfigured`.

When the endpoint status is `.discovering` (discovery pipeline running), a progress indicator
replaces the chart temporarily.

When the endpoint status is `.unreachable`, the chart shows a "Prometheus unreachable" banner with
a "Retry" button.

### ADR-0044 injection prevention

All placeholder substitution values (`{node}`, `{namespace}`, `{pod}`, `{workload}`) are validated
against the ADR-0044 whitelist regex `^[a-zA-Z0-9._-]{1,63}$` by `MetricsObservabilityActor` before
any PromQL expression is constructed. A value that fails validation causes the chart panel to render
a `#InvalidParameterError` inline message and writes a `PromQLInjectionAttemptBlocked` audit entry.
No Prometheus HTTP request is issued.

Label matchers use the anchored regex form `=~"^<value>$"` as required by ADR-0044.

## Pros and cons of the options

### Option A — Dedicated MetricsObservabilityView tab only

- Good, because no new dependency between `AppShell` and `metrics_observability` is introduced.
- Good, because Prometheus QPS is naturally bounded by the single dashboard surface.
- Bad, because operators must navigate away from the resource list to inspect trend data,
  breaking the situational awareness requirement.
- Bad, because the reference recording (R30) explicitly shows charts inside the detail drawer;
  parity is not achieved.

### Option B — Embedded sparkline (single series, no picker)

- Good, because the smallest possible UI surface keeps the drawer compact.
- Good, because a single PromQL template per kind family minimises maintenance.
- Bad, because single-series rendering does not surface capacity context (Usage vs Requests vs
  Allocatable vs Capacity) which operators need on Nodes.
- Bad, because no time-range control means operators cannot zoom out to inspect longer trends.

### Option C — Drawer chart with click-through to full dashboard (chosen)

- Good, because multi-series rendering gives operators the capacity context needed without
  leaving the drawer.
- Good, because the click-through to `MetricsObservabilityView` preserves the compact footprint
  while providing an escape hatch for deeper analysis.
- Good, because reuse of `MetricsObservabilityActor` means ADR-0016 caching and ADR-0044
  injection guard apply without additional plumbing.
- Bad, because adding `MetricsObservabilityActor` as a drawer view-model dependency introduces
  coupling between `AppShell` and the `metrics_observability` bounded context; the dependency
  must be injected through `AppShellDependencies` and must not reach into `domain_core` targets.
- Bad, because the series and time-range pickers add UI complexity for narrow drawer widths
  (280 pt); the picker may collapse to a secondary disclosure group.
- Bad, because aggregate workload queries require owner-reference label filtering which is not
  available via standard Prometheus labels in all kube-prometheus-stack versions; a fallback
  to namespace-scoped aggregate without workload filter must be defined.

## Followups

- ADR-0059 (proposed) — Full metrics dashboard tab layout: defines the full-height multi-panel
  layout for the MetricsObservabilityView tab that the "View in Metrics" click-through navigates
  to. Closes the remaining gap for R30.
- Update `docs/arch/contexts/metrics_observability/schemas/curated_query_set.cue` to include the
  Node four-series templates defined in this ADR.
- Rego policy `metrics_policy.rego` must be updated to enumerate the new template keys defined in
  this ADR so the injection guard can reject requests for unknown template names.
- A Gherkin feature for the full metrics tab click-through must be added once ADR-0059 is
  ratified.
- `workspace.dsl` must register `MetricChart` and `MetricChartViewModel` as components in the
  `App Shell` container with a dependency relationship to `MetricsObservabilityActor`.

## Confirmation

The feature is considered complete when:

1. Opening a Node detail drawer against a cluster with kube-prometheus-stack renders a four-series
   CPU chart (Usage, Requests, Allocatable, Capacity) within 2 seconds of the drawer opening.
2. Time-range switches (5m, 15m, 1h, 3h, 24h) reissue the query and re-render the chart within
   1 second of the switch.
3. With no Prometheus endpoint configured, the chart area renders the static hint "Configure
   Prometheus (Settings > Metrics) to see charts here" — no blank space, no crash.
4. Closing the detail drawer cancels all in-flight Prometheus queries for that drawer.
5. "View in Metrics" opens the full MetricsObservabilityView tab scoped to the current resource.
6. A unit test verifies that the 15-second cadence ceiling prevents a second query for the same
   `(endpointId, queryId)` pair from being issued within the 15-second window.
7. A unit test verifies that a node name failing ADR-0044 whitelist validation produces no HTTP
   request and a `PromQLInjectionAttemptBlocked` audit entry.

## More information

- ADR-0016 — Prometheus integration; HTTP client, curated PromQL templates, caching, graceful
  degradation.
- ADR-0044 — PromQL injection prevention; whitelist regex, Rego enforcement, audit entries.
- ADR-0051 — Multi-cluster workspace; drawer chrome layout specification (section "Detail drawer").
- Feature-gap analysis — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`,
  item R30.
- Gherkin feature — `docs/arch/contexts/metrics_observability/features/detail-drawer-metric-chart.feature`
  (written alongside this ADR).
