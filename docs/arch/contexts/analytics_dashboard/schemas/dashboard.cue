// DDD role: AggregateRoot
// Bounded context: analytics_dashboard
// Dashboard is the aggregate root representing a persistent, always-visible
// analytics surface scoped to one Kubernetes resource hierarchy level.

package analytics_dashboard

// UUIDv7 pattern: time-ordered UUID with version bits 7 and variant bits 8/9/a/b.
_#UUIDv7: string & =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// RFC 3339 timestamp pattern.
_#RFC3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

// ---- Aggregate Root ----

// Dashboard is the aggregate root. It binds a DashboardScope to a curated
// set of WidgetSlots and a Kubernetes context identity. Each combination of
// (kubernetesContextId, scope) maps to exactly one Dashboard in the catalog.
#Dashboard: {
	// Unique identifier. UUIDv7 — time-ordered for catalog sorting.
	id: _#UUIDv7

	// Scope discriminates which curated preset is used and which data sources
	// are queried by WidgetQueryDispatchService.
	scope: #DashboardScope

	// Identifies the Kubernetes context (cluster) this dashboard observes.
	// References the kubernetesContextId from cluster_connectivity.
	kubernetesContextId: _#UUIDv7

	// Ordered list of widget placements. Each slot references a widget from
	// the #AnalyticsWidget catalog and declares its grid position.
	layout: [...#WidgetSlot]

	// Auto-refresh interval in seconds. The dashboard UI refreshes all widget
	// data queries on this cadence. When macOS low-power mode is active the
	// effective interval is doubled by WidgetQueryDispatchService.
	refreshIntervalSeconds: 5 | 15 | 30 | 60
	refreshIntervalSeconds: 30

	// ISO 8601 / RFC 3339 timestamp when this dashboard record was first
	// persisted (either from a built-in preset or operator customisation).
	createdAt: _#RFC3339

	// ISO 8601 / RFC 3339 timestamp of the last mutation to layout or
	// refreshIntervalSeconds by the operator.
	updatedAt: _#RFC3339

	// True when the operator has modified the default ScopePreset layout.
	// DashboardCompositionService sets this flag on any layout mutation.
	// When false the dashboard is fully regenerated from the ScopePreset on
	// each application launch; when true the persisted layout is used.
	customisedByOperator: bool | *false
}

// ---- Scope discriminated union ----

// DashboardScope is a closed sum type. Exactly one variant is present per Dashboard.
// The variant determines which ScopePreset is loaded and which upstream ports are queried.
#DashboardScope:
	#ClusterOverviewScope |
	#NamespaceDetailScope |
	#PodDetailScope |
	#NodeDetailScope |
	#WorkloadDetailScope |
	#ServiceDetailScope |
	#HelmReleaseDetailScope |
	#DebugTimelineScope |
	#TopologyGraphScope

// Cluster-wide health and resource utilization overview.
// Sources: cluster_connectivity, metrics_observability.
#ClusterOverviewScope: {
	scopeKind: "cluster_overview"
}

// Single-namespace workload and resource breakdown.
// Sources: cluster_connectivity, metrics_observability, resource_browser.
#NamespaceDetailScope: {
	scopeKind: "namespace_detail"
	// Kubernetes namespace name. Must be a valid DNS label.
	namespace: string & !=""
}

// Single-pod deep inspection with container breakdown.
// Sources: metrics_observability, cluster_connectivity, resource_browser.
#PodDetailScope: {
	scopeKind: "pod_detail"
	// Kubernetes namespace containing the pod.
	namespace: string & !=""
	// Pod name within the namespace.
	podName: string & !=""
}

// Single-node kubelet metrics and condition panel.
// Sources: metrics_observability, cluster_connectivity.
#NodeDetailScope: {
	scopeKind: "node_detail"
	// Node name as it appears in kubectl get nodes.
	nodeName: string & !=""
}

// Workload replicas, rollout history, and pod restart overview.
// Applies to Deployment, StatefulSet, DaemonSet, and ReplicaSet.
// Sources: cluster_connectivity, metrics_observability.
#WorkloadDetailScope: {
	scopeKind: "workload_detail"
	// Kubernetes resource kind. Closed enum.
	kind: "Deployment" | "StatefulSet" | "DaemonSet" | "ReplicaSet"
	// Namespace containing the workload.
	namespace: string & !=""
	// Resource name within the namespace.
	name: string & !=""
}

// Service endpoint health and RED method latency dashboard.
// Sources: metrics_observability, cluster_connectivity.
#ServiceDetailScope: {
	scopeKind: "service_detail"
	// Namespace containing the service.
	namespace: string & !=""
	// Service name.
	name: string & !=""
}

// Helm release version history, manifest diff, and hook outcome panel.
// Sources: helm_management.
#HelmReleaseDetailScope: {
	scopeKind: "helm_release_detail"
	// Namespace where the Helm release is installed.
	namespace: string & !=""
	// Helm release name.
	releaseName: string & !=""
	// Specific revision number. Must be >= 1. When set to the latest
	// revision number, the diff viewer shows current vs previous.
	revision: int & >=1
}

// Cross-scope chronological event stream for post-mortem investigation.
// Combines Kubernetes events, audit mutations, and assistant tool calls.
// Sources: resource_browser, cluster_intelligence, cluster_connectivity.
#DebugTimelineScope: {
	scopeKind: "debug_timeline"
	// Time range to display, looking back from now.
	// Valid values: 15, 60, 360, 1440 (minutes).
	timeRangeMinutes: int & (15 | 60 | 360 | 1440)
	timeRangeMinutes: 60
}

// Interactive owner-reference and service-selector graph for topology exploration.
// Sources: cluster_connectivity, helm_management, resource_browser.
#TopologyGraphScope: {
	scopeKind: "topology_graph"
	// Optional label selector to anchor the graph root. When absent the
	// graph starts from all top-level workloads in the current context.
	// Format: standard Kubernetes label selector syntax.
	rootSelector?: string
}

// ---- Widget placement ----

// WidgetSlot places a named widget from the #AnalyticsWidget catalog into a
// grid cell. The grid is 12 columns wide; rowSpan and colSpan are in grid units.
#WidgetSlot: {
	// Refers to the widgetId field of the target #AnalyticsWidget entry in
	// the scope preset catalog.
	widgetId: string & !=""

	// Grid placement coordinates and span.
	position: #GridPosition
}

// Grid coordinate and span specification for a single widget slot.
#GridPosition: {
	// Zero-based row index in the dashboard grid.
	row: int & >=0

	// Zero-based column index in the 12-column grid.
	col: int & >=0 & <=11

	// Number of grid rows the widget occupies. Must be at least 1.
	rowSpan: int & >=1

	// Number of grid columns the widget occupies.
	// col + colSpan must not exceed 12.
	colSpan: int & >=1 & <=12
}
