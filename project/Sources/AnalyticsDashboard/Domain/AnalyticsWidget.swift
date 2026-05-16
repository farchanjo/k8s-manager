// Domain/AnalyticsWidget.swift — analytics_dashboard bounded context
// DDD role: ValueObject (sum type — closed discriminated union)
// Spec:      docs/arch/contexts/analytics_dashboard/schemas/analytics_widget.cue
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Swift 6 strict concurrency — all types are value types conforming to Sendable.

import Foundation

// MARK: - ColorSemantic

/// The closed set of semantic display colors for all widget types.
///
/// Arbitrary hex or RGB values are prohibited; only these five values are valid.
/// Mirrors `#ColorSemantic` in `analytics_widget.cue`.
public enum ColorSemantic: String, Sendable, Codable, Hashable, CaseIterable {
    /// Green — resource is healthy and all conditions are met.
    case healthy
    /// Yellow — degraded or approaching a threshold.
    case warning
    /// Red — error, critical, or condition failed.
    case error
    /// Blue — informational or currently selected.
    case info
    /// Gray — unknown state or no data available.
    case neutral
}

// MARK: - MetricUnit

/// Display units for numeric time-series values.
///
/// Mirrors `#MetricUnit` in `analytics_widget.cue`.
public enum MetricUnit: String, Sendable, Codable, Hashable, CaseIterable {
    case percent
    case bytes
    case count
    case perSecond = "per_second"
    case milliseconds
    case cores
}

// MARK: - ComparisonOperator

/// Comparison operator used in threshold evaluations for `CountWidget`.
///
/// Mirrors `#ComparisonOperator` in `analytics_widget.cue`.
public enum ComparisonOperator: String, Sendable, Codable, Hashable, CaseIterable {
    case greaterThan = ">"
    case lessThan = "<"
    case greaterThanOrEqual = ">="
    case lessThanOrEqual = "<="
    case equal = "="
}

// MARK: - EventTimelineSourceFilter

/// Source filter for `EventTimelineWidget`; controls which event streams are merged.
///
/// Mirrors the `sourceFilter` closed enum in `analytics_widget.cue`.
public enum EventTimelineSourceFilter: String, Sendable, Codable, Hashable, CaseIterable {
    case k8sEvents = "k8s_events"
    case mutationAudit = "mutation_audit"
    case assistantToolCalls = "assistant_tool_calls"
    case all
}

// MARK: - TopListOrder

/// Sort direction applied to `TopListWidget` PromQL results.
public enum TopListOrder: String, Sendable, Codable, Hashable, CaseIterable {
    case desc
    case asc
}

// MARK: - SeriesQuery

/// Pairs a display label with a PromQL template and a semantic color.
///
/// The `promQLTemplate` may contain `{namespace}`, `{pod}`, `{node}`,
/// `{service}`, `{container}`, `{release_name}` placeholders that
/// `WidgetQueryDispatchService` substitutes at query time from the active scope.
///
/// Mirrors `#SeriesQuery` in `analytics_widget.cue`.
public struct SeriesQuery: Sendable, Codable, Hashable {
    /// Human-readable series label shown in the chart legend.
    public let label: String

    /// PromQL expression template. Placeholders are substituted by scope.
    public let promQLTemplate: String

    /// Semantic color for this series line.
    public let color: ColorSemantic

    /// Designated initialiser.
    public init(label: String, promQLTemplate: String, color: ColorSemantic) {
        self.label = label
        self.promQLTemplate = promQLTemplate
        self.color = color
    }
}

// MARK: - Segment

/// Pairs a display label with a PromQL instant query and a semantic color
/// for use in stacked bar charts.
///
/// Mirrors `#Segment` in `analytics_widget.cue`.
public struct Segment: Sendable, Codable, Hashable {
    /// Human-readable segment label.
    public let label: String

    /// PromQL instant-vector query resolving to the segment value.
    public let query: String

    /// Semantic color for this segment.
    public let color: ColorSemantic

    /// Designated initialiser.
    public init(label: String, query: String, color: ColorSemantic) {
        self.label = label
        self.query = query
        self.color = color
    }
}

// MARK: - Threshold

/// A single conditional coloring rule for `CountWidget`.
///
/// The renderer evaluates `operator(metricValue, value)` and applies `color`
/// when the condition holds. Rules are evaluated in list order; the first
/// matching rule wins.
///
/// Mirrors `#Threshold` in `analytics_widget.cue`.
public struct Threshold: Sendable, Codable, Hashable {
    /// Comparison operator applied as: `metric_value <operator> value`.
    public let `operator`: ComparisonOperator

    /// Numeric threshold value for the comparison.
    public let value: Double

    /// Semantic color applied when the condition holds.
    public let color: ColorSemantic

    /// Short status label shown beneath the count tile (e.g., "Degraded").
    public let statusLabel: String

    /// Designated initialiser.
    public init(
        operator: ComparisonOperator,
        value: Double,
        color: ColorSemantic,
        statusLabel: String
    ) {
        self.operator = `operator`
        self.value = value
        self.color = color
        self.statusLabel = statusLabel
    }
}

// MARK: - ResourceRef

/// Identifies a Kubernetes resource by API coordinates.
///
/// Used by `DiffViewerWidget`, `ConditionsListWidget`, `TopologyGraphWidget`,
/// and `DrillDownEvent`.
///
/// Mirrors `#ResourceRef` in `analytics_widget.cue`.
public struct ResourceRef: Sendable, Codable, Hashable {
    /// Kubernetes API version (e.g., `"apps/v1"`, `"v1"`).
    public let apiVersion: String

    /// Kubernetes resource kind (e.g., `"Deployment"`, `"Service"`, `"Pod"`).
    public let kind: String

    /// Namespace. `nil` for cluster-scoped resources.
    public let namespace: String?

    /// Resource name.
    public let name: String

    /// Designated initialiser.
    public init(apiVersion: String, kind: String, namespace: String? = nil, name: String) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.namespace = namespace
        self.name = name
    }
}

// MARK: - DrillDownAction

/// Navigation intent encoded at the widget schema level.
///
/// `WidgetQueryDispatchService` forwards this to `DrillDownNavigator` when
/// an operator clicks an interactive data point.
///
/// Mirrors `#DrillDownAction` in `analytics_widget.cue`.
public struct DrillDownAction: Sendable, Codable, Hashable {
    /// Identifies the source widget within the current dashboard layout.
    public let sourceWidgetId: String

    /// The scope the navigator should transition to on click.
    public let targetScope: DashboardScope

    /// Mapping of drill-down parameters.
    public let parameterMapping: ParameterMapping

    /// Drill-down parameter bag.
    public struct ParameterMapping: Sendable, Codable, Hashable {
        /// The x-axis timestamp at the click location (RFC 3339 string).
        public let timestamp: String

        /// Optional pod name for scope transitions that require a pod identifier.
        public let podName: String?

        /// Designated initialiser.
        public init(timestamp: String = "click_x", podName: String? = nil) {
            self.timestamp = timestamp
            self.podName = podName
        }
    }

    /// Designated initialiser.
    public init(
        sourceWidgetId: String,
        targetScope: DashboardScope,
        parameterMapping: ParameterMapping = .init()
    ) {
        self.sourceWidgetId = sourceWidgetId
        self.targetScope = targetScope
        self.parameterMapping = parameterMapping
    }
}

// MARK: - WidgetActions

/// Optional primary and secondary drill-down actions for a widget.
///
/// Widgets that do not emit drill-down events omit this value.
///
/// Mirrors `#WidgetActions` in `analytics_widget.cue`.
public struct WidgetActions: Sendable, Codable, Hashable {
    /// Primary drill-down action; emitted when the operator clicks a data point.
    public let primaryDrillDown: DrillDownAction?

    /// Secondary drill-down action for widgets with dual click targets.
    public let secondaryDrillDown: DrillDownAction?

    /// Designated initialiser.
    public init(
        primaryDrillDown: DrillDownAction? = nil,
        secondaryDrillDown: DrillDownAction? = nil
    ) {
        self.primaryDrillDown = primaryDrillDown
        self.secondaryDrillDown = secondaryDrillDown
    }
}

// MARK: - AnalyticsWidget

/// Closed discriminated union of all renderable widget types.
///
/// The `kind` field encoded in the JSON payload is the discriminant for each
/// variant. Mirrors `#AnalyticsWidget` in `analytics_widget.cue`.
public enum AnalyticsWidget: Sendable, Codable, Hashable {
    case sparkline(SparklineWidget)
    case lineChart(LineChartWidget)
    case heatmap(HeatmapWidget)
    case stackedBar(StackedBarWidget)
    case count(CountWidget)
    case topList(TopListWidget)
    case eventTimeline(EventTimelineWidget)
    case topologyGraph(TopologyGraphWidget)
    case logErrorRate(LogErrorRateWidget)
    case diffViewer(DiffViewerWidget)
    case conditionsList(ConditionsListWidget)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case kind }

    private enum Kind: String, Codable {
        case sparkline
        case lineChart = "line_chart"
        case heatmap
        case stackedBar = "stacked_bar"
        case count
        case topList = "top_list"
        case eventTimeline = "event_timeline"
        case topologyGraph = "topology_graph"
        case logErrorRate = "log_error_rate"
        case diffViewer = "diff_viewer"
        case conditionsList = "conditions_list"
    }

    public init(from decoder: any Decoder) throws {
        let peek = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try peek.decode(Kind.self, forKey: .kind)
        let single = try decoder.singleValueContainer()
        switch kind {
        case .sparkline:
            self = .sparkline(try single.decode(SparklineWidget.self))
        case .lineChart:
            self = .lineChart(try single.decode(LineChartWidget.self))
        case .heatmap:
            self = .heatmap(try single.decode(HeatmapWidget.self))
        case .stackedBar:
            self = .stackedBar(try single.decode(StackedBarWidget.self))
        case .count:
            self = .count(try single.decode(CountWidget.self))
        case .topList:
            self = .topList(try single.decode(TopListWidget.self))
        case .eventTimeline:
            self = .eventTimeline(try single.decode(EventTimelineWidget.self))
        case .topologyGraph:
            self = .topologyGraph(try single.decode(TopologyGraphWidget.self))
        case .logErrorRate:
            self = .logErrorRate(try single.decode(LogErrorRateWidget.self))
        case .diffViewer:
            self = .diffViewer(try single.decode(DiffViewerWidget.self))
        case .conditionsList:
            self = .conditionsList(try single.decode(ConditionsListWidget.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .sparkline(let w):       try single.encode(w)
        case .lineChart(let w):       try single.encode(w)
        case .heatmap(let w):         try single.encode(w)
        case .stackedBar(let w):      try single.encode(w)
        case .count(let w):           try single.encode(w)
        case .topList(let w):         try single.encode(w)
        case .eventTimeline(let w):   try single.encode(w)
        case .topologyGraph(let w):   try single.encode(w)
        case .logErrorRate(let w):    try single.encode(w)
        case .diffViewer(let w):      try single.encode(w)
        case .conditionsList(let w):  try single.encode(w)
        }
    }

    /// The `widgetId` carried by any variant.
    public var widgetId: String {
        switch self {
        case .sparkline(let w):       return w.widgetId
        case .lineChart(let w):       return w.widgetId
        case .heatmap(let w):         return w.widgetId
        case .stackedBar(let w):      return w.widgetId
        case .count(let w):           return w.widgetId
        case .topList(let w):         return w.widgetId
        case .eventTimeline(let w):   return w.widgetId
        case .topologyGraph(let w):   return w.widgetId
        case .logErrorRate(let w):    return w.widgetId
        case .diffViewer(let w):      return w.widgetId
        case .conditionsList(let w):  return w.widgetId
        }
    }
}

// MARK: - Widget variant types

/// Compact 60-minute rolling time series for at-a-glance KPI display.
///
/// Mirrors `#SparklineWidget` in `analytics_widget.cue`.
public struct SparklineWidget: Sendable, Codable, Hashable {
    public let kind: String
    /// Unique identifier within the scope preset widget catalog.
    public let widgetId: String
    /// Display title shown above the sparkline.
    public let title: String
    /// PromQL template; single series only.
    public let promQLTemplate: String
    /// Rolling window in minutes. Default: 60.
    public let rangeMinutes: Int
    /// Display unit for value labels.
    public let unit: MetricUnit
    /// Optional drill-down actions.
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        promQLTemplate: String,
        rangeMinutes: Int = 60,
        unit: MetricUnit,
        actions: WidgetActions? = nil
    ) {
        self.kind = "sparkline"
        self.widgetId = widgetId
        self.title = title
        self.promQLTemplate = promQLTemplate
        self.rangeMinutes = rangeMinutes
        self.unit = unit
        self.actions = actions
    }
}

/// Multi-series time chart with configurable range and optional threshold overlay.
///
/// Mirrors `#LineChartWidget` in `analytics_widget.cue`.
public struct LineChartWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// One or more series queries; at least one is required.
    public let series: [SeriesQuery]
    public let rangeMinutes: Int
    /// Optional horizontal dashed threshold line value.
    public let threshold: Double?
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        series: [SeriesQuery],
        rangeMinutes: Int,
        threshold: Double? = nil,
        actions: WidgetActions? = nil
    ) {
        self.kind = "line_chart"
        self.widgetId = widgetId
        self.title = title
        self.series = series
        self.rangeMinutes = rangeMinutes
        self.threshold = threshold
        self.actions = actions
    }
}

/// Prometheus histogram bucket aggregation rendered as time-column color bands.
///
/// Always shows p50/p95/p99 simultaneously (invariant — spec §5).
/// Mirrors `#HeatmapWidget` in `analytics_widget.cue`.
public struct HeatmapWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// PromQL query selecting a Prometheus histogram metric.
    public let bucketsQuery: String
    /// Constrained to exactly `[50, 95, 99]` at the spec level.
    public let percentilesShown: [Int]
    public let rangeMinutes: Int
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        bucketsQuery: String,
        rangeMinutes: Int,
        actions: WidgetActions? = nil
    ) {
        self.kind = "heatmap"
        self.widgetId = widgetId
        self.title = title
        self.bucketsQuery = bucketsQuery
        self.percentilesShown = [50, 95, 99]
        self.rangeMinutes = rangeMinutes
        self.actions = actions
    }
}

/// Horizontal status count columns segmented by label and color.
///
/// Requires at least two segments. Mirrors `#StackedBarWidget`.
public struct StackedBarWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// At least two segments forming the stacked bar.
    public let segments: [Segment]
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        segments: [Segment],
        actions: WidgetActions? = nil
    ) {
        self.kind = "stacked_bar"
        self.widgetId = widgetId
        self.title = title
        self.segments = segments
        self.actions = actions
    }
}

/// Single numeric value tile with threshold-driven semantic color.
///
/// Mirrors `#CountWidget` in `analytics_widget.cue`.
public struct CountWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// PromQL instant-vector query resolving to the count value.
    public let query: String
    /// Ordered threshold rules; first matching rule wins.
    public let statusMapping: [Threshold]
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        query: String,
        statusMapping: [Threshold] = [],
        actions: WidgetActions? = nil
    ) {
        self.kind = "count"
        self.widgetId = widgetId
        self.title = title
        self.query = query
        self.statusMapping = statusMapping
        self.actions = actions
    }
}

/// Ranked list of top-N resources by a PromQL metric value.
///
/// Mirrors `#TopListWidget` in `analytics_widget.cue`.
public struct TopListWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    public let query: String
    /// Maximum number of entries to display. Default: 5.
    public let topN: Int
    public let orderBy: TopListOrder
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        query: String,
        topN: Int = 5,
        orderBy: TopListOrder = .desc,
        actions: WidgetActions? = nil
    ) {
        self.kind = "top_list"
        self.widgetId = widgetId
        self.title = title
        self.query = query
        self.topN = topN
        self.orderBy = orderBy
        self.actions = actions
    }
}

/// Scrollable filterable list of events from one or more sources.
///
/// Mirrors `#EventTimelineWidget` in `analytics_widget.cue`.
public struct EventTimelineWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    public let sourceFilter: EventTimelineSourceFilter
    public let rangeMinutes: Int
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        sourceFilter: EventTimelineSourceFilter,
        rangeMinutes: Int,
        actions: WidgetActions? = nil
    ) {
        self.kind = "event_timeline"
        self.widgetId = widgetId
        self.title = title
        self.sourceFilter = sourceFilter
        self.rangeMinutes = rangeMinutes
        self.actions = actions
    }
}

/// Interactive zoomable node-edge graph of resource relationships.
///
/// Supports PNG export. Mirrors `#TopologyGraphWidget` in `analytics_widget.cue`.
public struct TopologyGraphWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// Root resource reference from which graph traversal begins.
    public let rootRef: ResourceRef
    /// Maximum edge hops from the root node. Default: 3.
    public let depthLimit: Int
    /// When `true`, Service → Endpoints → Pod edges are included.
    public let includeServices: Bool
    /// When `true`, Pod → ReplicaSet → Deployment owner-reference edges are included.
    public let includeOwnerRefs: Bool
    /// When `true`, HelmRelease → managed-resource edges are included.
    public let includeHelmReleases: Bool
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        rootRef: ResourceRef,
        depthLimit: Int = 3,
        includeServices: Bool = true,
        includeOwnerRefs: Bool = true,
        includeHelmReleases: Bool = true,
        actions: WidgetActions? = nil
    ) {
        self.kind = "topology_graph"
        self.widgetId = widgetId
        self.title = title
        self.rootRef = rootRef
        self.depthLimit = depthLimit
        self.includeServices = includeServices
        self.includeOwnerRefs = includeOwnerRefs
        self.includeHelmReleases = includeHelmReleases
        self.actions = actions
    }
}

/// Log-line error rate sparkline computed by regex matching against pod log streams.
///
/// Clicking a spike opens the log viewer at the corresponding timestamp.
/// Mirrors `#LogErrorRateWidget` in `analytics_widget.cue`.
public struct LogErrorRateWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// Kubernetes namespace containing the target pod(s).
    public let namespace: String
    /// Label selector identifying the target pod(s).
    public let podSelector: String
    /// Regular expression applied to each log line to classify it as an error.
    public let regexErrorPattern: String
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        namespace: String,
        podSelector: String,
        regexErrorPattern: String = "(?i)(error|exception|failed|panic|fatal)",
        actions: WidgetActions? = nil
    ) {
        self.kind = "log_error_rate"
        self.widgetId = widgetId
        self.title = title
        self.namespace = namespace
        self.podSelector = podSelector
        self.regexErrorPattern = regexErrorPattern
        self.actions = actions
    }
}

/// Side-by-side or unified manifest diff between two resource versions.
///
/// Mirrors `#DiffViewerWidget` in `analytics_widget.cue`.
public struct DiffViewerWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// Left-side (older / baseline) resource reference.
    public let leftRef: ResourceRef
    /// Right-side (newer / current) resource reference.
    public let rightRef: ResourceRef
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        leftRef: ResourceRef,
        rightRef: ResourceRef,
        actions: WidgetActions? = nil
    ) {
        self.kind = "diff_viewer"
        self.widgetId = widgetId
        self.title = title
        self.leftRef = leftRef
        self.rightRef = rightRef
        self.actions = actions
    }
}

/// Compact indicator list for Kubernetes condition types.
///
/// Renders each condition as healthy, warning, or error based on
/// `Status` and `Reason` fields. Mirrors `#ConditionsListWidget`.
public struct ConditionsListWidget: Sendable, Codable, Hashable {
    public let kind: String
    public let widgetId: String
    public let title: String
    /// The resource whose `.status.conditions` array is rendered.
    public let resourceRef: ResourceRef
    public let actions: WidgetActions?

    public init(
        widgetId: String,
        title: String,
        resourceRef: ResourceRef,
        actions: WidgetActions? = nil
    ) {
        self.kind = "conditions_list"
        self.widgetId = widgetId
        self.title = title
        self.resourceRef = resourceRef
        self.actions = actions
    }
}
