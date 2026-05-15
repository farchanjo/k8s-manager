// DDD role: ValueObject
package app_shell

// #TrayMetricWidget is a sum type representing a single widget displayed
// in the NSPopover content area. Each widget variant carries the data
// needed by the TrayPresenter to issue the appropriate PromQL query and
// render the result with the correct visual treatment.
//
// Widget definitions are authored in the CUE schema and are not mutated
// at runtime. The operator can reorder widgets via TrayLayout but cannot
// change query templates or widget kinds without a settings migration.
#TrayMetricWidget:
	#SparklineWidget |
	#StackedBarWidget |
	#CountWidget |
	#RecentMutationsWidget |
	#ActiveSessionsWidget

// #SparklineWidget renders a time-series line chart (sparkline) using the
// Swift Charts framework LineMark primitive. It represents a single
// cluster-wide scalar metric sampled over the past rangeMinutes minutes
// at a resolution of samplePoints samples.
//
// Used for: CPU usage (percent), memory usage (bytes), network rx rate
// (per_second), network tx rate (per_second). Network rx/tx are rendered
// as a dual-line chart by combining two #SparklineWidget instances into a
// compound view; the TrayPresenter is responsible for this composition.
#SparklineWidget: {
	// kind is the discriminator for this sum type variant.
	kind: "sparkline"

	// id is a URL-safe slug that uniquely identifies the widget within
	// the tray layout. Used as the key in TrayLayout.widgetOrder and
	// as the widgetId field in RefreshFailed events so that the presenter
	// can mark the specific widget as degraded.
	id!: string & =~"^[a-z][a-z0-9-]*$"

	// title is the human-readable label displayed above the sparkline.
	// Rendered in the caption text style. Also used as the VoiceOver
	// accessibility label prefix (e.g. "CPU usage sparkline, current 38
	// percent").
	title!: string

	// promQLTemplate is the Prometheus query expression. The template
	// may reference the placeholder {{cluster}} which the TrayPresenter
	// replaces with the active context's Prometheus cluster label value
	// before issuing the query. In all_clusters_summary mode the
	// placeholder is omitted and the expression aggregates globally.
	promQLTemplate!: string

	// rangeMinutes is the time window of samples requested from
	// Prometheus via the /api/v1/query_range endpoint. Default is 60
	// minutes, matching the sparkline visual window.
	rangeMinutes: int & >=1 & <=1440 | *60

	// samplePoints is the number of data points requested in the range
	// query (the step parameter is derived as rangeMinutes*60/samplePoints
	// seconds). A higher value produces a smoother sparkline at the cost
	// of a larger response payload. Clamped to [60, 120].
	samplePoints: int & >=60 & <=120 | *60

	// yUnit controls the formatting of tooltip and accessibility value
	// annotations on the chart.
	//
	// "percent"    — values are formatted as "X%" (e.g. "38%").
	// "bytes"      — values are formatted using ByteCountFormatter
	//                 (e.g. "3.2 GB").
	// "count"      — values are formatted as plain integers.
	// "per_second" — values are formatted as "X/s" with SI prefix
	//                 (e.g. "1.2 MB/s").
	yUnit: "percent" | "bytes" | "count" | "per_second" | *"count"
}

// #StackedBarWidget renders a segmented horizontal bar chart. Each segment
// represents a subset of a population (e.g. pods in a given phase) and is
// coloured using a semantic status colour token from design_tokens.cue.
//
// Used for: pod phase distribution (Running/Pending/Failed).
#StackedBarWidget: {
	// kind is the discriminator for this sum type variant.
	kind: "stacked_bar"

	// id is the URL-safe slug for this widget.
	id!: string & =~"^[a-z][a-z0-9-]*$"

	// title is the human-readable label displayed above the bar.
	title!: string

	// segments is the ordered list of bar segments rendered left to right.
	// At least two segments are required for a stacked bar to be
	// meaningful. Segments are rendered in declaration order.
	segments: [_, _, ...] & [...#BarSegment]
}

// #BarSegment describes a single coloured subdivision of a #StackedBarWidget.
#BarSegment: {
	// label is displayed in the bar tooltip and in the VoiceOver
	// accessibility description.
	label!: string

	// color maps to a semantic status colour token in design_tokens.cue.
	// The TrayPresenter resolves the token to the appropriate NSColor for
	// the current appearance (light/dark).
	color: "healthy" | "warning" | "error" | "info"

	// promQLTemplate is the Prometheus instant query expression that
	// returns the count for this segment. The placeholder {{cluster}} is
	// substituted as in #SparklineWidget.
	promQLTemplate!: string
}

// #CountWidget renders a compact numeric cell showing a primary count and
// an optional "of N" denominator. Used for: nodes Ready/NotReady,
// namespaces total, deployments Available/Total, pods by phase.
//
// The cell background tint is determined by the statusMapping: if the
// primary count meets a threshold the cell is tinted with the corresponding
// status colour token.
#CountWidget: {
	// kind is the discriminator for this sum type variant.
	kind: "count"

	// id is the URL-safe slug for this widget.
	id!: string & =~"^[a-z][a-z0-9-]*$"

	// title is the label rendered above the numeric value.
	title!: string

	// primaryQuery is the Prometheus instant query that returns the
	// primary integer count (e.g. nodes in Ready condition).
	primaryQuery!: string

	// secondaryQuery, when present, provides the total denominator count
	// rendered as "X of N". For example, Deployments Available uses
	// primaryQuery for Available replicas and secondaryQuery for Total
	// replicas. Absent for metrics that have no natural denominator.
	secondaryQuery?: string

	// statusMapping defines threshold-based colour coding for the cell.
	// The TrayPresenter evaluates conditions in declaration order and
	// applies the colour of the first matching threshold. If no threshold
	// matches the cell is rendered without a tint.
	statusMapping: [...#StatusThreshold]
}

// #StatusThreshold maps a numeric threshold comparison to a semantic
// colour token. The comparison is: if primaryCount <operator> threshold,
// apply color.
#StatusThreshold: {
	// operator is the comparison to apply.
	operator: "less_than" | "greater_than" | "equal"

	// threshold is the numeric value to compare against.
	threshold!: number

	// color is the semantic status colour token to apply.
	color: "healthy" | "warning" | "error" | "info"
}

// #RecentMutationsWidget renders a scrollable list of recent mutating
// Kubernetes API operations sourced from MutationAuditReadModel in the
// resource_browser bounded context. Each row shows a relative timestamp,
// the operation verb, the resource kind and name, and an outcome icon
// (success/failure).
#RecentMutationsWidget: {
	// kind is the discriminator for this sum type variant.
	kind: "recent_mutations"

	// id is the URL-safe slug for this widget.
	id!: string & =~"^[a-z][a-z0-9-]*$"

	// limit is the maximum number of mutation records displayed.
	// The MutationAuditReadModel query is issued with ORDER BY
	// occurred_at DESC LIMIT <limit>. Default is 5.
	limit: int & >=1 & <=20 | *5
}

// #ActiveSessionsWidget renders a compact count chip for a specific
// session type. Three instances cover port-forwards, terminal sessions,
// and active AI diagnostic traces (cluster_intelligence MCPInvocationLog).
// Hovering over the port-forward chip reveals a tooltip listing the
// active tunnel specifications.
#ActiveSessionsWidget: {
	// kind is the discriminator for this sum type variant.
	kind: "active_sessions"

	// id is the URL-safe slug for this widget.
	id!: string & =~"^[a-z][a-z0-9-]*$"

	// sessionType selects the read model source for the count.
	//
	// "port_forward" — count from ActivePortForwardsReadModel in
	//                   port_forwarding bounded context.
	// "terminal"     — count from OpenTerminalsReadModel in
	//                   terminal_session bounded context.
	// "chat"         — count of active AI diagnostic traces from
	//                   MCPInvocationLogReadModel in cluster_intelligence.
	sessionType: "port_forward" | "terminal" | "chat"

	// showCount controls whether the numeric count is displayed. When
	// false the chip shows only the icon and label, hiding the count.
	// Default is true.
	showCount: bool | *true
}

// #TrayLayout captures the ordered sequence of widget IDs that the
// TrayPresenter renders in the popover content area. The order is
// operator-configurable via Settings > Tray > Widget Order. The
// TrayPresenter validates that every ID in widgetOrder references a
// known #TrayMetricWidget before rendering.
//
// The default sequence matches the ADR-0022 popover layout specification:
// sparklines first, stacked bar second, counts third, mutations fourth,
// sessions last.
#TrayLayout: {
	// widgetOrder is the prioritised list of widget IDs. The popover
	// renders widgets in this order from top to bottom. IDs not present
	// in this list are hidden. Duplicate IDs are invalid and rejected by
	// the settings migration guard.
	widgetOrder!: [...string & =~"^[a-z][a-z0-9-]*$"]
}
