# ADR-0059 — Resource list row metric mini-bars

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0016 (Prometheus integration), ADR-0036 (watch stream lifecycle),
  ADR-0050 (resource navigation taxonomy), ADR-0058 (detail-drawer Prometheus charts)
- Tags — mini-bars, sparkbar, node-list, metrics-observability, resource-browser

## Context and problem statement

The reference recording of Lens × Mirantis Desktop (`Screen Recording 2026-05-16 at 13.19.58.mov`,
gap-analysis item R21) shows the Node list with three inline per-row mini-bars: CPU usage, Memory
usage, and Disk usage. Each bar is a horizontal fill segment, colour-coded (blue / pink or magenta /
amber), capacity-relative, and animated as values change. The bars allow an operator to assess the
health of the entire node fleet at a glance without opening any detail drawer or navigating to a
separate metrics view.

K8S-Manager's current Node list (`NodesListView`) presents standard columns (Name, Status,
Conditions, Roles, Version, Age) with no live metric visualisation. Gap-analysis item R21 is
classified MISSING.

The questions this ADR must settle are:

- Which resource kinds surface per-row mini-bars and what metrics are shown?
- What data source drives the bars (Prometheus vs kubelet metrics summary)?
- What query strategy avoids N × 1 Prometheus round-trips for a list of N rows?
- What refresh cadence ceiling prevents query bursts while keeping the display live?
- How does the viewport (on-screen vs off-screen rows) affect query issuance?
- What is the fallback when no Prometheus endpoint is reachable?
- What is the SwiftUI view contract for a single mini-bar component?
- How does cluster disconnect affect the bars?
- What is the colour scheme and how does it encode utilisation intensity?

## Decision drivers

- **Visual fleet health at a glance** — operators managing large node fleets must assess CPU,
  memory, and disk pressure without opening each node individually. Per-row bars deliver
  this without a separate dashboard view.
- **Refresh cadence ceiling** — each batch query hits the Prometheus HTTP API. Over-frequent
  queries add load to both the Prometheus instance and the application network stack. A
  minimum inter-query interval of 15 seconds per kind is established as the ceiling.
- **Viewport awareness** — rows that are not visible (virtualised list scrolled past) must
  not trigger queries. The SwiftUI `onAppear` / `onDisappear` lifecycle drives query
  activation and cancellation at the row level for the Pod list. For the Node list, which is
  typically short, a single batch query covers all visible rows.
- **Kubelet metrics fallback** — Prometheus is optional (ADR-0016). When no Prometheus
  endpoint is discovered or reachable, the bars must still render using the kubelet
  `/metrics/resource` summary (CPU and memory only; disk is unavailable via kubelet
  summary). Bars remain visible with reduced fidelity rather than hiding entirely.
- **No per-row polling** — each row issuing its own periodic query violates the zero-polling
  spirit of ADR-0036 and would cause a query-storm for large Pod lists.
- **Swift concurrency safety** — all metric refresh tasks are owned by a dedicated actor
  (`NodeMetricsRefreshActor` in `metrics_observability`) to avoid shared mutable state
  reaching the view layer.

## Considered options

- **Option A — Poll Prometheus per row every N seconds.** Each `NodeRowView` owns a
  `Task` that fires a `GET /api/v1/query` request for its node name on a fixed timer.
  Simple to implement but produces N concurrent HTTP requests where N is the number of
  visible rows. For a 100-node cluster each 15-second tick issues 100 HTTP requests
  simultaneously. Rejected: query-storm risk; violates zero-polling principle from
  ADR-0036.
- **Option B — Subscribe to a Prometheus push webhook.** Prometheus Alertmanager or a
  remote-write receiver pushes updates to the application via a local HTTP listener.
  Requires the operator to configure Prometheus remote-write, introduces a local port
  listener, and is architecturally out of scope for a read-only macOS desktop client.
  Rejected: operational footprint, scope.
- **Option C — Single batch query for all visible rows with windowed range (chosen).**
  A shared `NodeMetricsRefreshActor` runs one Prometheus instant query per metric dimension
  (CPU, memory, disk) using a label-set match that returns values for all nodes in a single
  response. The actor throttles to one batch per kind per 15 seconds. Rows read from a
  shared `NodeMetricsReadModel` keyed by node name. For the Pod list, rows activate and
  deactivate their participation in the batch via `onAppear` / `onDisappear`, keeping the
  active node-name set current.

## Decision outcome

Chosen option — **Option C (batch query)**, because:

- One Prometheus round-trip per metric dimension serves all visible rows simultaneously,
  independent of fleet size.
- The shared `NodeMetricsReadModel` decouples the view layer from the query cadence;
  rows simply read from the model on each SwiftUI redraw cycle.
- Viewport-gated participation for Pod rows ensures that off-screen rows never contribute
  to query load.
- The fallback to kubelet metrics is a straightforward alternative data source for the same
  read model, requiring no change to the view layer.

### `MetricMiniBar` SwiftUI view contract

`MetricMiniBar` is a self-contained SwiftUI `View` in the `AppShell` module. Its declaration is:

```swift
struct MetricMiniBar: View {
    let value: Double          // current usage (same unit as capacity)
    let capacity: Double       // total capacity (must be > 0)
    let label: String          // short label shown on hover tooltip, e.g. "CPU"
    let color: Color           // fill colour; caller supplies from the colour scheme below
    let accessibilityLabel: String  // VoiceOver description, e.g. "CPU 42 percent"
}
```

The bar renders as a rounded-rectangle track (full width of the column cell) with a filled
segment proportional to `value / capacity`, clamped to `[0.0, 1.0]`. Width is 72 pt; height
is 6 pt. The fill colour is `color` at the saturation level described in the colour scheme
section. A hover tooltip shows `label: <formatted value> / <formatted capacity>` using
localised number formatting with two significant digits.

`MetricMiniBar` is stateless and has no internal timer. It receives already-computed values
from the enclosing row view model and redraws only when those values change. There is no
animation on value changes (values are replaced, not interpolated, to avoid visual noise
under burst updates).

### Per-kind metric registry

The following table defines which metric mini-bars appear per resource kind and which
PromQL queries or kubelet endpoints back each bar.

**Node list** — bars are always shown in the Name column cell (right-aligned, stacked
vertically, label icon only, no text label to save horizontal space):

- CPU usage — `node_cpu_busy_percent` (ADR-0016); capacity = number of allocatable CPUs
  (`kube_node_status_allocatable{resource="cpu"}`). Fallback: kubelet
  `/metrics/resource` `node_cpu_usage_seconds_total` rate over 60 s.
- Memory usage — `node_memory_working_set_bytes` derived from
  `node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes`; capacity =
  `kube_node_status_allocatable{resource="memory"}`. Fallback: kubelet
  `/metrics/resource` `node_memory_working_set_bytes`.
- Disk usage — `node_disk_io_utilization` (ADR-0016 curated query); capacity is
  expressed as a fraction (0.0–1.0) directly from the PromQL query output and does not
  require a separate capacity lookup. No kubelet fallback for disk (kubelet summary does
  not expose disk I/O utilisation).

**Pod list** — bars are shown only when the row is visible in the viewport
(`onAppear` / `onDisappear` drive activation in the shared query coordinator):

- CPU usage — `pod_cpu_usage_seconds` rate (ADR-0016); capacity = pod CPU request
  (`kube_pod_container_resource_requests{resource="cpu"}`). When no CPU request is set,
  the bar renders at 0 with a tooltip "no request set".
- Memory usage — `pod_memory_working_set_bytes` (ADR-0016); capacity = pod memory
  request (`kube_pod_container_resource_requests{resource="memory"}`). Same fallback
  as CPU when no request is set.

No mini-bars are defined for other resource kinds in this ADR. Additional kinds may be
added in a future ADR by extending the per-kind registry.

### Throttle policy

- One batch instant query is issued per metric dimension per kind per 15 seconds.
  "Batch" means a single PromQL expression that matches all nodes or all visible pods
  using a `{instance=~"<n1>|<n2>|..."}` or `{}` matcher that returns a vector of
  per-node or per-pod samples.
- The minimum inter-query interval (15 s) is a floor, not a ceiling. If the previous
  query has not yet returned when the next tick fires, the tick is skipped (no
  concurrent in-flight queries per dimension per kind).
- When the operator scrolls the Node list out of the visible area entirely (e.g.,
  the list view is hidden behind another tab), the periodic `Task` is suspended via
  `onDisappear` on the enclosing list view and resumed on `onAppear`. For the Pod list,
  individual rows register and deregister themselves with `NodeMetricsRefreshActor`.
- When the list is hidden, in-flight queries are not cancelled (they may still return
  before the view reappears); they are simply not scheduled again until the view
  reappears.

### Fallback to kubelet metrics

When `PrometheusDiscoveryService` (ADR-0016) reports that no Prometheus endpoint is
reachable for the active cluster, `NodeMetricsRefreshActor` switches to the kubelet
metrics summary path:

- For each node, a `GET` request is issued to the kube-apiserver proxy path
  `/api/v1/nodes/<nodeName>/proxy/metrics/resource`. The response is a Prometheus
  text-format exposition parsed by `KubeletMetricsParser` (a new type in
  `metrics_observability`).
- Only CPU and memory are available via this path. Disk bars are hidden (zero-width
  with a tooltip "disk unavailable without Prometheus") rather than shown at 0.
- The 15-second throttle applies identically to kubelet requests.
- If both Prometheus and kubelet proxy requests fail for a given node, that node's
  bars are shown in grey at 0 with a tooltip "metrics unavailable".

### Colour scheme

The fill colour of each `MetricMiniBar` encodes both the metric dimension and the
utilisation intensity:

- **CPU** — base colour `Color.blue`. Saturation ramps from 40% at 0% utilisation to
  100% at 90%+ utilisation. Above 90% the fill shifts to `Color.red` to signal
  pressure. Threshold is configurable per cluster in settings (default 90%).
- **Memory** — base colour `Color(hue: 0.83, saturation: 1.0, brightness: 0.9)` (a
  magenta / pink). Same 40%→100% saturation ramp. Red shift at 90% threshold.
- **Disk** — base colour `Color.orange` (amber). Same saturation ramp. Red shift at
  90% threshold.

The colour values are defined as static constants in `MetricMiniBarColours` (a new
enum in `AppShell/Views/Resources/`) rather than inline in `MetricMiniBar`.

### Cluster disconnect behaviour

When `ClusterSessionActor` emits a `disconnected` state event:

- `NodeMetricsRefreshActor` receives the state change via its subscription to the
  cluster session stream.
- All pending query tasks for that cluster are cancelled.
- The `NodeMetricsReadModel` entries for all nodes in that cluster are set to a
  `frozen` state with the last known values retained.
- `MetricMiniBar` reads the `frozen` flag from the row view model and renders the bar
  in grey (desaturated to 20%) with a tooltip "cluster disconnected — metrics frozen".
- When the cluster reconnects, the `frozen` flag clears, the actor resumes the
  15-second tick, and bars return to normal colour on the next successful query.

### Consequences

Positive:

- Operators can assess the health of the entire node fleet from the list view without
  opening any detail drawer.
- The batch query strategy scales linearly with Prometheus capacity, not with fleet
  size; a single round-trip serves all rows.
- Kubelet fallback means the feature degrades gracefully in clusters without Prometheus,
  offering CPU and memory data from an always-available source.
- The frozen-bar behaviour on disconnect provides an honest representation of data
  staleness without removing the bars entirely.

Negative:

- `NodeMetricsRefreshActor` introduces a new long-lived actor in `metrics_observability`
  that must be wired into `AppShellDependencies` and tested for concurrent-access
  correctness.
- The kubelet proxy path issues one HTTP request per node per 15 seconds, which may be
  perceptible on clusters with many nodes if Prometheus is absent and the operator has
  the Node list open continuously.
- Disk utilisation is entirely unavailable without Prometheus; operators on clusters
  without Prometheus will see partial bars with a tooltip explanation, which may
  prompt questions about why disk is missing.

## Pros and cons of the options

### Option A — Poll per row

- Good, because each row is self-contained; no shared actor is needed.
- Bad, because N rows produce N concurrent requests per tick; a 500-node cluster would
  issue 500 Prometheus HTTP requests every 15 seconds.
- Bad, because per-row `Task` creation and cancellation produces significant actor-hop
  overhead in the SwiftUI update cycle.

### Option B — Prometheus push webhook

- Good, because the application receives updates reactively rather than polling.
- Bad, because it requires the operator to configure Prometheus remote-write to a local
  listener, which is invasive and incompatible with read-only desktop client semantics.
- Bad, because it requires a local HTTP server, adding a network surface to the
  application sandbox.

### Option C — Batch query with viewport gating (chosen)

- Good, because one round-trip serves all visible rows regardless of fleet size.
- Good, because viewport gating ensures that off-screen rows do not contribute to query
  load.
- Good, because the read-model pattern decouples view rendering from query cadence.
- Bad, because it requires a shared `NodeMetricsRefreshActor` and a new
  `NodeMetricsReadModel` type, adding implementation surface.

## Confirmation

- `MetricMiniBar` renders a filled track proportional to `value / capacity`, clamped to
  `[0.0, 1.0]`, with correct colour for each of the three dimensions in a SwiftUI preview.
- `NodeMetricsRefreshActor` issues at most one in-flight query per dimension per kind;
  a unit test that advances a mock clock by 14 seconds verifies no second query is issued;
  advancing by 15 seconds verifies the second query fires.
- A unit test verifies that when `ClusterSessionActor` emits `disconnected`, all
  `NodeMetricsReadModel` entries transition to `frozen` and no further queries are issued
  until `connected` is received.
- A unit test with a mock Prometheus HTTP client verifies that the batch query for the
  Node list uses a single instant-query request returning a vector of per-node samples, not
  one request per node.
- A unit test verifies that when `PrometheusDiscoveryService` reports no endpoint,
  `NodeMetricsRefreshActor` switches to the kubelet proxy path and issues requests to
  `/api/v1/nodes/<nodeName>/proxy/metrics/resource` for each node in the active set.
- `AccessibilityLabel` on `MetricMiniBar` is verified to contain the metric name and
  percentage in a UI test using `XCUIApplication`.
- Gherkin feature `resource_browser/features/node-row-live-mini-bars.feature` passes all
  five scenarios.

## Followups

- ADR-0062 (node conditions chip) will add a fourth cell element to the Node row; the
  column layout spec must be revised to accommodate both the conditions chip and the three
  mini-bars without overflow at the minimum supported window width (1024 pt).
- Consider extending the per-kind metric registry to Deployment rows (CPU / memory
  aggregate for all pods in the deployment) in a follow-on ADR once the Node and Pod
  implementations are confirmed.
- The 90% threshold for colour shift to red should be exposed as a per-cluster preference
  in the settings UI once the settings schema is extended (tracked in the local_persistence
  backlog).

## More information

- ADR-0016 — Prometheus integration; defines `PrometheusHTTPClient`, curated PromQL queries
  (`node_cpu_busy_percent`, `node_disk_io_utilization`, `pod_cpu_usage_seconds`, etc.),
  5-second in-memory cache, and the kubelet proxy fallback concept.
- ADR-0036 — Watch stream lifecycle; zero-polling invariant that motivates the batch-query
  approach over per-row polling.
- ADR-0050 — Resource navigation taxonomy; defines the Node list as a first-class resource
  view and the tab ownership model that determines when the Node list is visible.
- ADR-0058 — Embedded Prometheus charts in the resource detail drawer; a companion ADR that
  specifies the per-resource time-series chart used in the detail drawer. Mini-bars (this ADR)
  are instant-value bar charts in the list; drawer charts (ADR-0058) are range-query
  time-series charts. Both share `PrometheusHTTPClient` and the in-memory cache from ADR-0016.
- Feature gap analysis — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`,
  section 5.4, item R21.
