// DDD role: ValueObject
// Bounded context: analytics_dashboard
// AnalyticsWidget is the closed sum type for all renderable widget variants.
// Each variant carries its own configuration; the kind field is the discriminant.

package analytics_dashboard

// ---- Color semantic enum ----

// ColorSemantic is the only permitted set of colors across all widget types.
// Arbitrary hex or RGB values are rejected by this constraint.
// green=healthy, red=error/critical, yellow=warning/degraded,
// blue=informational/selected, gray=unknown/no-data.
#ColorSemantic: "healthy" | "warning" | "error" | "info" | "neutral"

// ---- Unit enum ----

// MetricUnit enumerates the display units for numeric series.
#MetricUnit: "percent" | "bytes" | "count" | "per_second" | "milliseconds" | "cores"

// ---- Comparison operator enum ----

// ComparisonOperator for threshold evaluations.
#ComparisonOperator: ">" | "<" | ">=" | "<=" | "="

// ---- Shared sub-types ----

// SeriesQuery pairs a display label with a PromQL template and a semantic color.
// The promQLTemplate may contain {namespace}, {pod}, {node}, {service} placeholders
// that WidgetQueryDispatchService substitutes at query time from the active scope.
#SeriesQuery: {
	// Human-readable series label shown in the chart legend.
	label: string & !=""

	// PromQL expression template. Placeholders: {namespace}, {pod},
	// {node}, {service}, {container}, {release_name}.
	promQLTemplate: string & !=""

	// Semantic color for this series line.
	color: #ColorSemantic
}

// Segment pairs a display label with a PromQL query and a semantic color
// for use in stacked bar charts.
#Segment: {
	// Human-readable segment label.
	label: string & !=""

	// PromQL instant-vector query resolving to the segment value.
	query: string & !=""

	// Semantic color for this segment.
	color: #ColorSemantic
}

// Threshold defines a single conditional coloring rule for Count widgets.
// The widget renderer evaluates operator(value, threshold.value) and applies
// threshold.color when the condition holds. Rules are evaluated in list order;
// the first matching rule wins.
#Threshold: {
	// Comparison operator applied as: metric_value <operator> threshold_value.
	operator: #ComparisonOperator

	// Numeric threshold value for the comparison.
	value: number

	// Semantic color applied when the condition holds.
	color: #ColorSemantic

	// Short status label shown beneath the count tile (e.g., "Degraded", "Critical").
	statusLabel: string & !=""
}

// ResourceRef identifies a Kubernetes resource by API coordinates.
// Used by DiffViewer, ConditionsList, and TopologyGraph widgets.
#ResourceRef: {
	// Kubernetes API version (e.g., "apps/v1", "v1").
	apiVersion: string & !=""

	// Kubernetes resource kind (e.g., "Deployment", "Service", "Pod").
	kind: string & !=""

	// Namespace. Absent for cluster-scoped resources.
	namespace?: string

	// Resource name.
	name: string & !=""
}

// DrillDownAction describes the navigation intent emitted when the operator
// clicks an interactive data point in a widget. WidgetQueryDispatchService
// forwards this to DrillDownNavigator.
#DrillDownAction: {
	// Identifies the source widget within the current dashboard layout.
	sourceWidgetId: string & !=""

	// The scope the navigator should transition to on click.
	targetScope: #DashboardScope

	// Mapping of drill-down parameters.
	// timestamp: x-axis value at the click point, RFC 3339 string.
	// podName: resolved pod name when clicking a pod-level data point.
	parameterMapping: {
		// The x-axis timestamp at the click location.
		timestamp: string | *"click_x"

		// Optional pod name for scope transitions that require a pod identifier.
		podName?: string
	}
}

// WidgetActions bundles the optional drill-down actions for a widget.
// Widgets that do not emit drill-down events omit this field.
#WidgetActions: {
	// Primary drill-down action. Emitted when the operator clicks a data point.
	primaryDrillDown?: #DrillDownAction

	// Secondary drill-down action for widgets with dual click targets
	// (e.g., heatmap column vs row header).
	secondaryDrillDown?: #DrillDownAction
}

// ---- Widget sum type ----

// AnalyticsWidget is the closed discriminated union of all renderable widget types.
// The kind field is the discriminant; each variant carries its own typed configuration.
#AnalyticsWidget:
	#SparklineWidget |
	#LineChartWidget |
	#HeatmapWidget |
	#StackedBarWidget |
	#CountWidget |
	#TopListWidget |
	#EventTimelineWidget |
	#TopologyGraphWidget |
	#LogErrorRateWidget |
	#DiffViewerWidget |
	#ConditionsListWidget

// Sparkline — compact 60-minute rolling time series for at-a-glance KPI display.
// Rendered as a small area chart without axes. Suitable for sidebar KPI rows.
#SparklineWidget: {
	kind: "sparkline"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title shown above the sparkline.
	title: string & !=""

	// PromQL template. Single series only. Placeholders substituted by scope.
	promQLTemplate: string & !=""

	// Rolling window in minutes. Default and only validated value is 60.
	rangeMinutes: int & >=1 | *60

	// Display unit for value labels.
	unit: #MetricUnit

	// Optional drill-down actions for click events.
	actions?: #WidgetActions
}

// LineChart — multi-series time chart with configurable range and optional
// static threshold overlay. Used for CPU/memory trend with request/limit lines.
#LineChartWidget: {
	kind: "line_chart"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// One or more series queries. Each resolves to a labeled colored line.
	series: [...#SeriesQuery] & [_, ...]

	// Query range window in minutes.
	rangeMinutes: int & >=1

	// Optional horizontal threshold line value (e.g., memory limit in bytes).
	// The renderer draws a dashed line at this value across all series.
	threshold?: float64

	// Optional drill-down actions.
	actions?: #WidgetActions
}

// Heatmap — Prometheus histogram bucket aggregation rendered as time-column
// color bands. Always shows p50/p95/p99 simultaneously to surface bimodal
// distributions. Used for service latency on ServiceDetail scope.
#HeatmapWidget: {
	kind: "heatmap"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// PromQL query selecting a Prometheus native histogram or classic histogram
	// metric. WidgetQueryDispatchService computes percentile buckets from this.
	bucketsQuery: string & !=""

	// Percentile set to display. Constrained to exactly [50, 95, 99].
	// Single-percentile heatmaps are not permitted (mask bimodal distributions).
	percentilesShown: [50, 95, 99]

	// Query range window in minutes.
	rangeMinutes: int & >=1

	// Optional drill-down actions (e.g., click column → drill to logs at timestamp).
	actions?: #WidgetActions
}

// StackedBar — horizontal status count columns segmented by label and color.
// Used for pod phase distribution (Running / Pending / Failed / Succeeded / Unknown).
#StackedBarWidget: {
	kind: "stacked_bar"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// Two or more segments forming the stacked bar.
	segments: [...#Segment] & [_, _, ...]

	// Optional drill-down actions.
	actions?: #WidgetActions
}

// Count — single numeric value tile with threshold-driven semantic color.
// Used for nodes ready, deployment availability, namespace count.
#CountWidget: {
	kind: "count"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title shown above the count value.
	title: string & !=""

	// PromQL instant-vector query resolving to the count value.
	query: string & !=""

	// Ordered threshold rules. First matching rule determines the tile color.
	// When no rule matches the tile renders with color "neutral".
	statusMapping: [...#Threshold]

	// Optional drill-down actions.
	actions?: #WidgetActions
}

// TopList — ranked list of top-N resources by a PromQL metric value.
// Used for top namespaces by CPU/memory, top pods by restart count.
#TopListWidget: {
	kind: "top_list"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// PromQL instant-vector query. The result set is sorted by value and
	// truncated to topN entries. Label set from each sample provides the
	// row display name (WidgetQueryDispatchService selects the most
	// informative label key: pod, namespace, node, etc.).
	query: string & !=""

	// Maximum number of entries to display.
	topN: int & >=1 | *5

	// Sort direction applied to the PromQL result values.
	orderBy: "desc" | "asc"

	// Optional drill-down actions (e.g., click row → drill to namespace/pod detail).
	actions?: #WidgetActions
}

// EventTimeline — scrollable filterable list of events from one or more sources.
// Sources can be Kubernetes object events, mutation audit log, or assistant tool calls.
#EventTimelineWidget: {
	kind: "event_timeline"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// Source filter controls which event streams are merged into the timeline.
	// "all" merges all available streams for the current scope.
	sourceFilter: "k8s_events" | "mutation_audit" | "assistant_tool_calls" | "all"

	// Look-back window in minutes from the current time.
	rangeMinutes: int & >=1

	// Optional drill-down actions (e.g., click event → drill to resource detail).
	actions?: #WidgetActions
}

// TopologyGraph — interactive zoomable node-edge graph of resource relationships.
// Edges are owner references, service selector matches, or Helm release ownership.
// Supports PNG export.
#TopologyGraphWidget: {
	kind: "topology_graph"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// Root resource reference from which graph traversal begins.
	rootRef: #ResourceRef

	// Maximum edge hops from the root node. Prevents infinite expansion in
	// deeply nested owner chains.
	depthLimit: int & >=1 | *3

	// When true, Service → Endpoints → Pod edges are included in the graph.
	includeServices: bool | *true

	// When true, Pod → ReplicaSet → Deployment owner-reference edges are included.
	includeOwnerRefs: bool | *true

	// When true, HelmRelease → managed-resource edges are included.
	includeHelmReleases: bool | *true

	// Optional drill-down actions (e.g., click node → drill to detail scope).
	actions?: #WidgetActions
}

// LogErrorRate — sparkline of log-line error rate over time computed by regex
// matching against pod log streams. Includes a data link: clicking a spike
// opens the log viewer at the corresponding timestamp.
#LogErrorRateWidget: {
	kind: "log_error_rate"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// Kubernetes namespace containing the target pod(s).
	namespace: string & !=""

	// Label selector identifying the target pod(s) for log streaming.
	// Standard Kubernetes label selector syntax.
	podSelector: string & !=""

	// Regular expression applied to each log line to classify it as an error.
	// Case-insensitive by default via the (?i) flag in the default value.
	regexErrorPattern: string | *"(?i)(error|exception|failed|panic|fatal)"

	// Optional drill-down actions. Default action: click spike → #DrillToLogs
	// with timestampRFC3339 set to click x-axis value.
	actions?: #WidgetActions
}

// DiffViewer — side-by-side or unified manifest diff between two resource versions.
// Used on HelmReleaseDetail scope to compare revision N vs N-1.
#DiffViewerWidget: {
	kind: "diff_viewer"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// Left-side (older / baseline) resource reference.
	leftRef: #ResourceRef

	// Right-side (newer / current) resource reference.
	rightRef: #ResourceRef

	// Optional drill-down actions.
	actions?: #WidgetActions
}

// ConditionsList — compact indicator list for Kubernetes condition types.
// Renders each condition as a green checkmark, red X, or yellow warning icon
// based on the condition's Status and Reason fields.
#ConditionsListWidget: {
	kind: "conditions_list"

	// Unique identifier within the scope preset widget catalog.
	widgetId: string & !=""

	// Display title.
	title: string & !=""

	// The resource whose .status.conditions array is rendered.
	resourceRef: #ResourceRef

	// Optional drill-down actions.
	actions?: #WidgetActions
}
