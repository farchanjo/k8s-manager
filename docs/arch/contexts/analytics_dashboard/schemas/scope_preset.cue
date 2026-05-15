// DDD role: ValueObject
// Bounded context: analytics_dashboard
// ScopePreset defines the curated default widget layout for each DashboardScope variant.
// DashboardCompositionService loads the matching preset when an operator selects a
// scope for the first time and #Dashboard.customisedByOperator == false.

package analytics_dashboard

// ---- ScopePreset aggregate ----

// ScopePreset is an immutable value object shipped with the application.
// Each preset is identified by a stable kebab-case slug that matches the
// scopeKind of the corresponding #DashboardScope variant.
#ScopePreset: {
	// Stable slug identifier. Must match a scopeKind in #DashboardScope.
	presetId: string & !=""

	// Human-readable display name shown in the scope picker.
	label: string & !=""

	// Ordered list of widget placements forming the default layout.
	// Row and column positions follow a 12-column grid.
	defaultLayout: [...#WidgetSlot] & [_, ...]
}

// ---- ClusterOverview preset ----

#ClusterOverviewPreset: #ScopePreset & {
	presetId: "cluster_overview"
	label:    "Cluster Overview"

	defaultLayout: [
		// Row 0: node and pod status counts (4 tiles across)
		{widgetId: "nodes-ready-count",       position: {row: 0, col: 0,  rowSpan: 1, colSpan: 3}},
		{widgetId: "pods-phase-stacked-bar",  position: {row: 0, col: 3,  rowSpan: 1, colSpan: 5}},
		{widgetId: "namespace-count",         position: {row: 0, col: 8,  rowSpan: 1, colSpan: 2}},
		{widgetId: "deployments-available",   position: {row: 0, col: 10, rowSpan: 1, colSpan: 2}},

		// Row 1: cluster-wide CPU and memory sparklines
		{widgetId: "cluster-cpu-sparkline",   position: {row: 1, col: 0,  rowSpan: 1, colSpan: 6}},
		{widgetId: "cluster-mem-sparkline",   position: {row: 1, col: 6,  rowSpan: 1, colSpan: 6}},

		// Row 2: top namespaces by resource consumption
		{widgetId: "top-namespaces-cpu",      position: {row: 2, col: 0,  rowSpan: 2, colSpan: 6}},
		{widgetId: "top-namespaces-mem",      position: {row: 2, col: 6,  rowSpan: 2, colSpan: 6}},

		// Row 4: recent cluster-level events
		{widgetId: "recent-cluster-events",   position: {row: 4, col: 0,  rowSpan: 2, colSpan: 12}},
	]
}

// ---- NamespaceDetail preset ----

#NamespaceDetailPreset: #ScopePreset & {
	presetId: "namespace_detail"
	label:    "Namespace Detail"

	defaultLayout: [
		// Row 0: workload kind breakdown + pod phase bar
		{widgetId: "workload-kind-stacked-bar",   position: {row: 0, col: 0,  rowSpan: 1, colSpan: 6}},
		{widgetId: "ns-pods-phase-stacked-bar",   position: {row: 0, col: 6,  rowSpan: 1, colSpan: 6}},

		// Row 1: CPU and memory usage vs requests vs limits line charts
		{widgetId: "ns-cpu-requests-limits",      position: {row: 1, col: 0,  rowSpan: 2, colSpan: 6}},
		{widgetId: "ns-mem-requests-limits",      position: {row: 1, col: 6,  rowSpan: 2, colSpan: 6}},

		// Row 3: network I/O sparklines
		{widgetId: "ns-network-in-sparkline",     position: {row: 3, col: 0,  rowSpan: 1, colSpan: 6}},
		{widgetId: "ns-network-out-sparkline",    position: {row: 3, col: 6,  rowSpan: 1, colSpan: 6}},

		// Row 4: top pods by CPU and memory
		{widgetId: "top-pods-cpu",                position: {row: 4, col: 0,  rowSpan: 2, colSpan: 6}},
		{widgetId: "top-pods-mem",                position: {row: 4, col: 6,  rowSpan: 2, colSpan: 6}},

		// Row 6: recent namespace events
		{widgetId: "ns-recent-events",            position: {row: 6, col: 0,  rowSpan: 2, colSpan: 12}},
	]
}

// ---- PodDetail preset ----

#PodDetailPreset: #ScopePreset & {
	presetId: "pod_detail"
	label:    "Pod Detail"

	defaultLayout: [
		// Row 0: CPU and memory time-series with overlays (RED: utilization first)
		{widgetId: "pod-cpu-line-chart",          position: {row: 0, col: 0,  rowSpan: 2, colSpan: 6}},
		{widgetId: "pod-mem-line-chart",          position: {row: 0, col: 6,  rowSpan: 2, colSpan: 6}},

		// Row 2: restart count and log error rate (saturation + errors)
		{widgetId: "pod-restart-count",           position: {row: 2, col: 0,  rowSpan: 1, colSpan: 3}},
		{widgetId: "pod-log-error-rate",          position: {row: 2, col: 3,  rowSpan: 1, colSpan: 5}},
		{widgetId: "pod-oomkilled-count",         position: {row: 2, col: 8,  rowSpan: 1, colSpan: 4}},

		// Row 3: network I/O time-series
		{widgetId: "pod-net-rx-sparkline",        position: {row: 3, col: 0,  rowSpan: 1, colSpan: 6}},
		{widgetId: "pod-net-tx-sparkline",        position: {row: 3, col: 6,  rowSpan: 1, colSpan: 6}},

		// Row 4: disk I/O sparklines
		{widgetId: "pod-disk-read-sparkline",     position: {row: 4, col: 0,  rowSpan: 1, colSpan: 6}},
		{widgetId: "pod-disk-write-sparkline",    position: {row: 4, col: 6,  rowSpan: 1, colSpan: 6}},

		// Row 5: events timeline (full width)
		{widgetId: "pod-events-timeline",         position: {row: 5, col: 0,  rowSpan: 2, colSpan: 12}},
	]
}

// ---- NodeDetail preset ----

#NodeDetailPreset: #ScopePreset & {
	presetId: "node_detail"
	label:    "Node Detail"

	defaultLayout: [
		// Row 0: node conditions list + pod density count
		{widgetId: "node-conditions-list",        position: {row: 0, col: 0,  rowSpan: 2, colSpan: 4}},
		{widgetId: "node-pod-density-count",      position: {row: 0, col: 4,  rowSpan: 1, colSpan: 4}},
		{widgetId: "node-capacity-allocatable",   position: {row: 0, col: 8,  rowSpan: 1, colSpan: 4}},

		// Row 2: CPU and memory utilization line charts (USE: utilization)
		{widgetId: "node-cpu-line-chart",         position: {row: 2, col: 0,  rowSpan: 2, colSpan: 6}},
		{widgetId: "node-mem-line-chart",         position: {row: 2, col: 6,  rowSpan: 2, colSpan: 6}},

		// Row 4: disk pressure and image GC sparklines (USE: saturation)
		{widgetId: "node-disk-pressure-sparkline",position: {row: 4, col: 0,  rowSpan: 1, colSpan: 6}},
		{widgetId: "node-image-gc-sparkline",     position: {row: 4, col: 6,  rowSpan: 1, colSpan: 6}},

		// Row 5: top consuming pods on this node
		{widgetId: "node-top-pods-cpu",           position: {row: 5, col: 0,  rowSpan: 2, colSpan: 6}},
		{widgetId: "node-top-pods-mem",           position: {row: 5, col: 6,  rowSpan: 2, colSpan: 6}},
	]
}

// ---- WorkloadDetail preset ----

#WorkloadDetailPreset: #ScopePreset & {
	presetId: "workload_detail"
	label:    "Workload Detail"

	defaultLayout: [
		// Row 0: replica status count tiles
		{widgetId: "workload-replicas-desired",   position: {row: 0, col: 0,  rowSpan: 1, colSpan: 3}},
		{widgetId: "workload-replicas-available", position: {row: 0, col: 3,  rowSpan: 1, colSpan: 3}},
		{widgetId: "workload-rollout-progress",   position: {row: 0, col: 6,  rowSpan: 1, colSpan: 6}},

		// Row 1: replicas over time line chart
		{widgetId: "workload-replicas-line-chart",position: {row: 1, col: 0,  rowSpan: 2, colSpan: 8}},
		{widgetId: "workload-pod-restart-rate",   position: {row: 1, col: 8,  rowSpan: 2, colSpan: 4}},

		// Row 3: rollout history events and pod restart count
		{widgetId: "workload-rollout-events",     position: {row: 3, col: 0,  rowSpan: 2, colSpan: 12}},
	]
}

// ---- ServiceDetail preset (RED method layout) ----

#ServiceDetailPreset: #ScopePreset & {
	presetId: "service_detail"
	label:    "Service Detail"

	// RED method: rate left, error rate left-adjacent, latency right.
	defaultLayout: [
		// Row 0: endpoints count + selector match status
		{widgetId: "svc-endpoints-count",         position: {row: 0, col: 0,  rowSpan: 1, colSpan: 3}},
		{widgetId: "svc-selector-match-count",    position: {row: 0, col: 3,  rowSpan: 1, colSpan: 3}},
		{widgetId: "svc-error-rate-count",        position: {row: 0, col: 6,  rowSpan: 1, colSpan: 3}},
		{widgetId: "svc-p99-latency-count",       position: {row: 0, col: 9,  rowSpan: 1, colSpan: 3}},

		// Row 1-2: request rate (left) + error rate (left-adjacent) line charts
		{widgetId: "svc-request-rate-line-chart", position: {row: 1, col: 0,  rowSpan: 2, colSpan: 4}},
		{widgetId: "svc-error-rate-line-chart",   position: {row: 1, col: 4,  rowSpan: 2, colSpan: 4}},

		// Row 1-4: latency heatmap p50/p95/p99 (right, taller for bimodal visibility)
		{widgetId: "svc-latency-heatmap",         position: {row: 1, col: 8,  rowSpan: 4, colSpan: 4}},

		// Row 3-4: request rate and error rate continuation
		{widgetId: "svc-rps-sparkline",           position: {row: 3, col: 0,  rowSpan: 1, colSpan: 4}},
		{widgetId: "svc-error-sparkline",         position: {row: 3, col: 4,  rowSpan: 1, colSpan: 4}},
	]
}

// ---- HelmReleaseDetail preset ----

#HelmReleaseDetailPreset: #ScopePreset & {
	presetId: "helm_release_detail"
	label:    "Helm Release Detail"

	defaultLayout: [
		// Row 0: release version timeline + hook outcomes
		{widgetId: "helm-revision-count",         position: {row: 0, col: 0,  rowSpan: 1, colSpan: 3}},
		{widgetId: "helm-hook-outcomes",          position: {row: 0, col: 3,  rowSpan: 1, colSpan: 9}},

		// Row 1-4: manifest diff viewer (full width, tall for readability)
		{widgetId: "helm-manifest-diff",          position: {row: 1, col: 0,  rowSpan: 6, colSpan: 12}},

		// Row 7: release events timeline
		{widgetId: "helm-release-events",         position: {row: 7, col: 0,  rowSpan: 2, colSpan: 12}},
	]
}

// ---- DebugTimeline preset ----

#DebugTimelinePreset: #ScopePreset & {
	presetId: "debug_timeline"
	label:    "Debug Timeline"

	defaultLayout: [
		// Row 0: source filter summary counts
		{widgetId: "debug-k8s-event-count",       position: {row: 0, col: 0,  rowSpan: 1, colSpan: 4}},
		{widgetId: "debug-mutation-count",        position: {row: 0, col: 4,  rowSpan: 1, colSpan: 4}},
		{widgetId: "debug-tool-call-count",       position: {row: 0, col: 8,  rowSpan: 1, colSpan: 4}},

		// Row 1-end: unified event timeline (full width, expandable)
		{widgetId: "debug-unified-timeline",      position: {row: 1, col: 0,  rowSpan: 8, colSpan: 12}},
	]
}

// ---- TopologyGraph preset ----

#TopologyGraphPreset: #ScopePreset & {
	presetId: "topology_graph"
	label:    "Topology Graph"

	defaultLayout: [
		// Row 0: node and edge count summary tiles
		{widgetId: "topo-node-count",             position: {row: 0, col: 0,  rowSpan: 1, colSpan: 3}},
		{widgetId: "topo-edge-count",             position: {row: 0, col: 3,  rowSpan: 1, colSpan: 3}},
		{widgetId: "topo-helm-release-count",     position: {row: 0, col: 6,  rowSpan: 1, colSpan: 3}},
		{widgetId: "topo-service-count",          position: {row: 0, col: 9,  rowSpan: 1, colSpan: 3}},

		// Row 1-end: interactive topology graph (full width, tall)
		{widgetId: "topo-graph-widget",           position: {row: 1, col: 0,  rowSpan: 10, colSpan: 12}},
	]
}
