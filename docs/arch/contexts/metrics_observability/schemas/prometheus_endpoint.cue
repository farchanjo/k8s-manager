// DDD role: AggregateRoot
// Bounded context: metrics_observability
// Represents a discovered or manually configured Prometheus endpoint
// scoped to one Kubernetes context.

package metrics_observability

#PrometheusEndpoint: {
	// Stable identifier for this endpoint record. UUIDv7 format.
	id: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// Reference to the KubernetesContext this endpoint belongs to. UUIDv7 format.
	kubernetes_context_id: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// Base URL of the Prometheus HTTP API. Must use http or https scheme.
	url: =~"^https?://.+"

	// How this endpoint was discovered or configured.
	// auto_label      — Service with label app.kubernetes.io/name=prometheus
	// auto_annotation — Service with annotation prometheus.io/scrape=true
	// well_known      — fixed kube-prometheus-stack in-cluster address
	// manual_override — operator-supplied URL in per-cluster settings
	discovery_source: "auto_label" | "auto_annotation" | "well_known" | "manual_override"

	// Authentication strategy for requests to this endpoint.
	// none             — no Authorization header (in-cluster, no proxy)
	// bearer_inherit   — forward bearer token from current KubernetesSession
	// bearer_explicit  — separate bearer token supplied by the operator in settings
	auth_strategy: "none" | "bearer_inherit" | "bearer_explicit"

	// When true, TLS certificate verification is skipped for this endpoint.
	// Default is false. Operator opt-in only; must not be set automatically.
	insecure_skip_tls_verify: bool | *false

	// Connectivity and authentication status as determined by the last health probe.
	// unknown      — no probe has been attempted yet
	// healthy      — last probe returned HTTP 200
	// unreachable  — connection refused, timeout, or DNS failure
	// unauthorized — HTTP 401 or 403 received
	status: "unknown" | "healthy" | "unreachable" | "unauthorized"

	// ISO 8601 / RFC 3339 timestamp of the last health probe attempt.
	// Absent when no probe has been attempted.
	last_probed_at_rfc3339?: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// Prometheus server version string returned by the /-/metadata or build_info endpoint.
	// Absent until a successful probe has been completed.
	// Example: "3.7.1"
	version?: string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+(-.+)?$"
}
