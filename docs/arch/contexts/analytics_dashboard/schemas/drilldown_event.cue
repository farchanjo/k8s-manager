// DDD role: ValueObject
// Bounded context: analytics_dashboard
// DrillDownEvent is the closed sum type for all navigation intents emitted by
// interactive widgets. DrillDownNavigator domain service handles each variant.

package analytics_dashboard

// ---- DrillDownEvent sum type ----

// DrillDownEvent is emitted when an operator clicks an interactive data point
// in any widget. DrillDownNavigator resolves the variant and performs the
// corresponding navigation: scope change, log viewer open, YAML viewer open,
// or filtered event timeline open.
#DrillDownEvent:
	#DrillToScope |
	#DrillToLogs |
	#DrillToYAML |
	#DrillToEvents

// ---- Common fields (embedded by all variants) ----

// _#DrillBase carries the provenance fields shared by all DrillDownEvent variants.
// CUE struct embedding is used; each variant declares these fields directly.
// The `...` open marker allows variants to add discriminator and payload fields.
_#DrillBase: {
	// Dashboard aggregate root that owns the source widget.
	sourceDashboardId: _#UUIDv7

	// Widget identifier within the source dashboard layout.
	sourceWidgetId: string & !=""
	...
}

// ---- DrillToScope ----

// DrillToScope navigates the dashboard to a different DashboardScope.
// Emitted by topology graph node clicks, top-list row clicks, count tile clicks,
// and stacked bar segment clicks.
#DrillToScope: _#DrillBase & {
	eventKind: "drill_to_scope"

	// The dashboard scope the navigator should transition to.
	targetScope: #DashboardScope
}

// ---- DrillToLogs ----

// DrillToLogs opens the log viewer in resource_browser at a specific timestamp.
// Emitted by LogErrorRate widget spike clicks and heatmap column clicks.
// The AuditTimelinePort opens the log stream positioned at timestampRFC3339 ± 30s.
#DrillToLogs: _#DrillBase & {
	eventKind: "drill_to_logs"

	// Kubernetes namespace containing the target pod(s).
	namespace: string & !=""

	// Label selector identifying the target pod(s).
	// Standard Kubernetes label selector syntax.
	podName: string & !=""

	// RFC 3339 timestamp at which the log viewer should be positioned.
	// Typically the x-axis value at the click point.
	timestampRFC3339: _#RFC3339
}

// ---- DrillToYAML ----

// DrillToYAML opens the YAML resource viewer in resource_browser for a specific
// Kubernetes resource. Emitted by topology graph node clicks and diff viewer
// side-panel clicks.
#DrillToYAML: _#DrillBase & {
	eventKind: "drill_to_yaml"

	// The resource to display in the YAML viewer.
	resourceRef: #ResourceRef
}

// ---- DrillToEvents ----

// DrillToEvents opens a filtered event timeline scoped to a specific resource
// and time range. Emitted by workload replica chart clicks, node condition
// indicator clicks, and pod restart count tile clicks.
#DrillToEvents: _#DrillBase & {
	eventKind: "drill_to_events"

	// The resource whose events should be displayed.
	resourceRef: #ResourceRef

	// Look-back window in minutes from the click timestamp.
	// Constraining to the same valid set as DebugTimelineScope.
	timeRangeMinutes: 15 | 60 | 360 | 1440 | *60
}
