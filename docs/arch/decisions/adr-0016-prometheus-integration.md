# ADR-0016 — Prometheus integration: auto-discovery, HTTP client, and curated PromQL dashboards

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — prometheus, metrics, observability, auto-discovery, promql, http-client, swift-concurrency, urlsession, codable

## Context and problem statement

K8sManager provides a resource browser, port-forwarding, and terminal access for Kubernetes clusters.
Operators regularly need to inspect CPU, memory, network, and API-server health without leaving the
application. Native Kubernetes metrics (via the Metrics Server) expose only instantaneous CPU and
memory for Pods and Nodes. They do not support historical queries, rate calculations, or composite
indicators such as API-server error rates or workload restart rates.

Prometheus, when deployed in-cluster (most commonly via kube-prometheus-stack), stores time-series
data and exposes a REST HTTP API that any client can query with PromQL. K8sManager must integrate
with that API to render curated dashboards for Pods, Nodes, and the API-server directly inside the
application.

The questions this ADR must settle are:

- How does K8sManager discover the Prometheus endpoint for a cluster?
- What happens when no Prometheus is present?
- How is authentication handled for Prometheus endpoints exposed inside and outside the cluster?
- What HTTP client strategy is used to call the Prometheus REST API?
- Which PromQL queries are pre-defined and what are their default range and step parameters?
- What caching policy applies to repeated queries?
- What is the confirmation criterion for the implementation?

## Decision drivers

- K8sManager uses URLSession and Codable throughout; no third-party networking library is in scope.
- No public Swift package for Prometheus query exists; an in-house HTTP client is required.
- The application is macOS-native. Network calls must use async/await and Swift structured concurrency.
- Security: bearer tokens must never persist to disk. Prometheus auth follows the same session-scoped
  token strategy used by KubernetesApiPort.
- UX: dashboards must render within 1 second when kube-prometheus-stack is installed and healthy.
- Graceful degradation: when no Prometheus is reachable, the UI shows an actionable explanation, not
  a blank panel.
- Discovery must be transparent to the operator for the common case (kube-prometheus-stack) and
  configurable for atypical deployments.

## Considered options

### Option A — Auto-discovery only (no manual override)

Perform automated Service-scan discovery on every cluster connection. Surface results in the UI but
provide no mechanism for the operator to override them. If discovery fails, the metrics panel
remains disabled.

Rejected. Real-world clusters expose Prometheus behind ingress controllers, service meshes, or
external load balancers. Service-scan cannot locate those endpoints. Operators with non-standard
deployments would be permanently blocked.

### Option B — Manual URL only

Require the operator to supply the Prometheus base URL in per-cluster settings before the metrics
panel activates. No automatic detection.

Rejected. The most common case — kube-prometheus-stack installed with default chart values — would
require every operator to look up and enter the URL manually despite the endpoint being
deterministic and discoverable. Onboarding friction is unacceptable.

### Option C — Auto-discovery with manual override and well-known fallback (selected)

Run a three-tier discovery pipeline in order:

1. Well-known endpoint: probe `http://prometheus-operated.monitoring.svc:9090/-/healthy` (default
   kube-prometheus-stack in-cluster address). If the probe returns HTTP 200, use this endpoint.
2. Service label scan: list all Services in all namespaces via `/api/v1/services`. Return the first
   Service where the label `app.kubernetes.io/name=prometheus` is present. Derive the base URL from
   the Service cluster IP and the first TCP port with name `web` or `http` or port 9090.
3. Service annotation scan: same listing pass, but match `prometheus.io/scrape=true` on the Service
   object.

Steps 2 and 3 share a single API call. If multiple candidates emerge, the first sorted by namespace
then name becomes the default; all candidates are surfaced in settings as alternatives.

When auto-discovery produces a result the operator can still enter a manual URL in per-cluster
settings. A manual URL always takes precedence over any auto-detected candidate.

When discovery produces no candidates, the metrics panel shows an empty-state view with a hint
linking to kube-prometheus-stack installation documentation.

This option covers the common case transparently, handles non-standard deployments, and degrades
gracefully.

## Decision outcome

K8sManager implements Option C.

### Discovery pipeline

The discovery pipeline runs once when a cluster context becomes active. Results are stored in the
`PrometheusEndpointRepository` (backed by local_persistence / SQLite) with a `discoverySource`
field indicating which tier produced the result.

The pipeline is implemented as `PrometheusDiscoveryService`, a Domain Service in the
`metrics_observability` bounded context. It depends on `KubernetesApiPort` for the Service listing
and on `SettingsRepository` (local_persistence) for reading and writing manual overrides.

Discovery sources and their precedence order:

1. `manual_override` — operator-supplied URL in per-cluster settings. Highest precedence. The
   pipeline skips tiers 2–4 when a manual override is stored.
2. `well_known` — fixed URL `http://prometheus-operated.monitoring.svc:9090`. Probed via a HEAD
   request to `/-/healthy`. Used when the probe returns 2xx.
3. `auto_label` — Service with `app.kubernetes.io/name=prometheus`.
4. `auto_annotation` — Service with `prometheus.io/scrape=true`.

When multiple candidates are found via auto_label or auto_annotation, the first sorted by
(namespace ASC, name ASC) becomes the active endpoint. All candidates are written to the repository
so the settings UI can offer selection.

### HTTP client

The Prometheus HTTP client is a standalone Swift type of approximately 340 lines,
`PrometheusHTTPClient`, located in the `metrics_observability` module. It uses `URLSession` and
`Codable` exclusively. There is no dependency on any public package.

Supported endpoints:

- `GET /api/v1/query` — instant query
- `GET /api/v1/query_range` — range query
- `GET /api/v1/series` — series metadata
- `GET /api/v1/labels` — label names

All requests are issued with `URLSession.data(for:)` using Swift structured concurrency. Responses
are decoded through a generic `PrometheusAPIResponse<T>` envelope where `T` is one of:

- `InstantVectorResult` — `resultType == "vector"`, decoded as `[Sample]`
- `RangeMatrixResult` — `resultType == "matrix"`, decoded as `[Series]`
- `ScalarResult` — `resultType == "scalar"`, decoded as a single `(timestamp, value)` pair
- `StringResult` — `resultType == "string"`, decoded as a single string

Decoding errors for unrecognised result types surface as `PrometheusClientError.unsupportedResultType`.

Query timeout is 30 seconds (configurable via a property on `PrometheusHTTPClient`, not a global).

### Authentication

Two strategies are supported, mapped to the `authStrategy` field of `PrometheusEndpoint`:

- `none` — no `Authorization` header is added. Used for in-cluster endpoints accessible via the
  kubeconfig service-account token path already established by KubernetesApiPort.
- `bearer_inherit` — the bearer token already held in the current `KubernetesSession` (from
  kubeconfig or service-account mount) is forwarded on every request. This covers the common case
  where Prometheus is behind kube-rbac-proxy or an OIDC-protected ingress that accepts the same
  cluster credential.
- `bearer_explicit` — a separate bearer token supplied by the operator in per-cluster settings.
  Used when Prometheus is exposed outside the cluster (e.g., behind an ingress with its own
  authentication mechanism independent of the cluster credential).

Bearer tokens are held in memory for the duration of the session. They are not written to SQLite or
to the macOS Keychain. On session teardown the token reference is released.

When a `401 Unauthorized` response is received while using `bearer_inherit`, the application
triggers a re-authentication pass through `KubernetesApiPort` and retries the request once. If the
retry also fails, the endpoint status is set to `unauthorized` and the metrics panel surfaces an
actionable message.

When using `bearer_explicit` and a `401` is received, no automatic retry is performed. The
operator must update the token in settings.

### Caching

A short-lived cache stores the last result per `(endpointId, expr, queryParams)` key with a TTL of
5 seconds. The cache is purely in-memory (a `Dictionary` behind an `actor`). Its purpose is to
prevent redundant HTTP requests when the same PromQL expression is rendered in multiple UI
components simultaneously (e.g., a summary card and a full chart for the same Pod).

The cache does not persist across application launches. It does not apply to series or label
queries (metadata calls).

### PromQL curated queries

The application ships a compile-time set of curated PromQL templates covering the following
categories and queries:

CPU:
- `pod_cpu_usage_seconds` — rate of CPU seconds consumed by a Pod container group over 2 minutes.
  Placeholder: `{namespace}`, `{podName}`.
- `node_cpu_busy_percent` — 1 minus the idle fraction across all CPU modes for a Node.
  Placeholder: `{node}`.

Memory:
- `pod_memory_working_set_bytes` — working-set bytes for a Pod. Placeholder: `{namespace}`,
  `{podName}`.
- `node_memory_available_bytes` — available memory on a Node. Placeholder: `{node}`.

Network:
- `pod_network_rx_bytes_rate` — receive byte rate for a Pod's network interface over 2 minutes.
  Placeholder: `{namespace}`, `{podName}`.
- `pod_network_tx_bytes_rate` — transmit byte rate for a Pod. Placeholder: `{namespace}`,
  `{podName}`.

Disk:
- `node_disk_io_utilization` — fraction of time the disk was busy on a Node. Placeholder: `{node}`.

API server:
- `apiserver_request_rate` — total API-server request rate over 1 minute.
- `apiserver_5xx_rate` — 5xx error rate from the API server.
- `apiserver_p99_latency` — 99th-percentile request latency in seconds.

Workload health:
- `workload_replicas_available` — available replicas for a Deployment or StatefulSet.
  Placeholder: `{namespace}`.
- `workload_restart_rate` — rate of container restarts over 15 minutes. Placeholder: `{namespace}`.

Default range for all curated queries: last 60 minutes, step 30 seconds.

Templates use curly-brace placeholders (`{namespace}`, `{podName}`, `{node}`) that are substituted
at query time from the currently selected resource context in the resource_browser.

Downsampling: when a query result contains more than 200 data points the application downsamples to
exactly 200 points using uniform index sampling before passing data to the chart renderer. This
keeps rendering time bounded regardless of step granularity.

### No subprocess

All Prometheus communication is via the HTTP API described above. The application does not invoke
`kubectl`, `promtool`, or any external binary. There is no subprocess or XPC bridge for metrics.

## Positive consequences

- Operators using kube-prometheus-stack get working dashboards with zero configuration.
- Operators with non-standard deployments retain full control via manual URL override.
- No third-party Swift dependency is introduced; the client is auditable and maintainable.
- Bearer tokens never touch disk; the security posture matches the existing KubernetesApiPort
  token handling.
- Curated queries cover the most common diagnostic scenarios without requiring PromQL knowledge.

## Negative consequences

- The in-house HTTP client requires ongoing maintenance as the Prometheus API evolves.
- The 5-second in-memory cache provides limited protection against burst requests; applications
  with many simultaneous chart views may still issue parallel HTTP calls.
- Discovery cannot locate Prometheus endpoints that are not represented as Kubernetes Services
  (e.g., external Prometheus reachable only by DNS alias not backed by a Service object). These
  require manual override.

## Confirmation

The feature is considered complete when:

1. Against a cluster with kube-prometheus-stack installed and default chart values, all 12 curated
   dashboard panels render within 1 second of the user navigating to the metrics view for a Pod or
   Node that has at least one data point in the last 60 minutes.
2. Against a cluster without any Prometheus installation, the metrics panel shows an empty-state
   view with a hint message referencing kube-prometheus-stack installation steps. No unhandled error
   or blank panel is shown.
3. All three auto-discovery tiers (well_known, auto_label, auto_annotation) are covered by unit
   tests with mock HTTP responses.
4. Manual URL override is tested end-to-end: entering a URL in settings causes the override to take
   precedence over any auto-detected candidate.
5. Bearer token re-authentication (bearer_inherit, 401 retry) is covered by a unit test using a
   mock URLSession.

## More information

- ADR-0005 — Bounded contexts MVP (defines metrics_observability context)
- ADR-0006 — MVP+ scope (adds Prometheus integration to the roadmap)
- ADR-0010 — Local persistence (SQLite backing for PrometheusEndpointRepository)
- ADR-0011 — Swift concurrency conventions (applies to PrometheusQueryActor and client)
- ADR-0013 — Resource browser scope (defines Pod and Node selection that feeds curated queries)
