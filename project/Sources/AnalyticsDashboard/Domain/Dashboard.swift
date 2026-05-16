// Domain/Dashboard.swift — analytics_dashboard bounded context
// DDD role: AggregateRoot
// Spec:      docs/arch/contexts/analytics_dashboard/schemas/dashboard.cue
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Swift 6 strict concurrency — all types are value types conforming to Sendable.

import Foundation

// MARK: - DashboardScope

/// Closed sum type that discriminates which curated preset is loaded
/// and which upstream ports `WidgetQueryDispatchService` queries.
///
/// Mirrors `#DashboardScope` in `dashboard.cue`.
public enum DashboardScope: Sendable, Codable, Hashable {
    case clusterOverview
    case namespaceDetail(namespace: String)
    case podDetail(namespace: String, podName: String)
    case nodeDetail(nodeName: String)
    case workloadDetail(kind: WorkloadKind, namespace: String, name: String)
    case serviceDetail(namespace: String, name: String)
    case helmReleaseDetail(namespace: String, releaseName: String, revision: Int)
    case debugTimeline(timeRangeMinutes: DebugTimeRange)
    case topologyGraph(rootSelector: String?)

    // MARK: Codable — tagged representation matching `scopeKind` in CUE

    private enum CodingKeys: String, CodingKey {
        case scopeKind, namespace, podName, nodeName, kind, name, releaseName, revision,
             timeRangeMinutes, rootSelector
    }

    private enum ScopeKind: String, Codable {
        case clusterOverview = "cluster_overview"
        case namespaceDetail = "namespace_detail"
        case podDetail = "pod_detail"
        case nodeDetail = "node_detail"
        case workloadDetail = "workload_detail"
        case serviceDetail = "service_detail"
        case helmReleaseDetail = "helm_release_detail"
        case debugTimeline = "debug_timeline"
        case topologyGraph = "topology_graph"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let scopeKind = try c.decode(ScopeKind.self, forKey: .scopeKind)
        switch scopeKind {
        case .clusterOverview:
            self = .clusterOverview
        case .namespaceDetail:
            self = .namespaceDetail(namespace: try c.decode(String.self, forKey: .namespace))
        case .podDetail:
            self = .podDetail(
                namespace: try c.decode(String.self, forKey: .namespace),
                podName: try c.decode(String.self, forKey: .podName)
            )
        case .nodeDetail:
            self = .nodeDetail(nodeName: try c.decode(String.self, forKey: .nodeName))
        case .workloadDetail:
            self = .workloadDetail(
                kind: try c.decode(WorkloadKind.self, forKey: .kind),
                namespace: try c.decode(String.self, forKey: .namespace),
                name: try c.decode(String.self, forKey: .name)
            )
        case .serviceDetail:
            self = .serviceDetail(
                namespace: try c.decode(String.self, forKey: .namespace),
                name: try c.decode(String.self, forKey: .name)
            )
        case .helmReleaseDetail:
            self = .helmReleaseDetail(
                namespace: try c.decode(String.self, forKey: .namespace),
                releaseName: try c.decode(String.self, forKey: .releaseName),
                revision: try c.decode(Int.self, forKey: .revision)
            )
        case .debugTimeline:
            self = .debugTimeline(timeRangeMinutes: try c.decode(DebugTimeRange.self, forKey: .timeRangeMinutes))
        case .topologyGraph:
            self = .topologyGraph(rootSelector: try c.decodeIfPresent(String.self, forKey: .rootSelector))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clusterOverview:
            try c.encode(ScopeKind.clusterOverview, forKey: .scopeKind)
        case .namespaceDetail(let ns):
            try c.encode(ScopeKind.namespaceDetail, forKey: .scopeKind)
            try c.encode(ns, forKey: .namespace)
        case .podDetail(let ns, let pod):
            try c.encode(ScopeKind.podDetail, forKey: .scopeKind)
            try c.encode(ns, forKey: .namespace)
            try c.encode(pod, forKey: .podName)
        case .nodeDetail(let node):
            try c.encode(ScopeKind.nodeDetail, forKey: .scopeKind)
            try c.encode(node, forKey: .nodeName)
        case .workloadDetail(let kind, let ns, let name):
            try c.encode(ScopeKind.workloadDetail, forKey: .scopeKind)
            try c.encode(kind, forKey: .kind)
            try c.encode(ns, forKey: .namespace)
            try c.encode(name, forKey: .name)
        case .serviceDetail(let ns, let name):
            try c.encode(ScopeKind.serviceDetail, forKey: .scopeKind)
            try c.encode(ns, forKey: .namespace)
            try c.encode(name, forKey: .name)
        case .helmReleaseDetail(let ns, let release, let rev):
            try c.encode(ScopeKind.helmReleaseDetail, forKey: .scopeKind)
            try c.encode(ns, forKey: .namespace)
            try c.encode(release, forKey: .releaseName)
            try c.encode(rev, forKey: .revision)
        case .debugTimeline(let range):
            try c.encode(ScopeKind.debugTimeline, forKey: .scopeKind)
            try c.encode(range, forKey: .timeRangeMinutes)
        case .topologyGraph(let sel):
            try c.encode(ScopeKind.topologyGraph, forKey: .scopeKind)
            try c.encodeIfPresent(sel, forKey: .rootSelector)
        }
    }

    /// Stable slug identifier matching the scope preset `presetId`.
    public var presetId: String {
        switch self {
        case .clusterOverview:       return "cluster_overview"
        case .namespaceDetail:       return "namespace_detail"
        case .podDetail:             return "pod_detail"
        case .nodeDetail:            return "node_detail"
        case .workloadDetail:        return "workload_detail"
        case .serviceDetail:         return "service_detail"
        case .helmReleaseDetail:     return "helm_release_detail"
        case .debugTimeline:         return "debug_timeline"
        case .topologyGraph:         return "topology_graph"
        }
    }
}

// MARK: - WorkloadKind

/// Kubernetes workload resource kinds supported by `WorkloadDetailScope`.
///
/// Mirrors the closed enum in `dashboard.cue#WorkloadDetailScope`.
public enum WorkloadKind: String, Sendable, Codable, Hashable, CaseIterable {
    case deployment = "Deployment"
    case statefulSet = "StatefulSet"
    case daemonSet = "DaemonSet"
    case replicaSet = "ReplicaSet"
}

// MARK: - DebugTimeRange

/// Valid look-back windows for `DebugTimelineScope`.
///
/// Mirrors the constrained int `15 | 60 | 360 | 1440` in `dashboard.cue`.
public enum DebugTimeRange: Int, Sendable, Codable, Hashable, CaseIterable {
    case fifteenMinutes = 15
    case oneHour = 60
    case sixHours = 360
    case oneDay = 1440
}

// MARK: - RefreshInterval

/// Valid auto-refresh cadences for a `Dashboard`.
///
/// Mirrors `refreshIntervalSeconds: 5 | 15 | 30 | 60` in `dashboard.cue`.
public enum RefreshInterval: Int, Sendable, Codable, Hashable, CaseIterable {
    case fiveSeconds = 5
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60

    /// Default cadence per the CUE schema (30 s).
    public static let `default` = RefreshInterval.thirtySeconds
}

// MARK: - GridPosition

/// Row/col/rowSpan/colSpan placement in a 12-column dashboard grid.
///
/// Invariant: `col + colSpan <= 12` — enforced by `DashboardCompositionService`.
///
/// Mirrors `#GridPosition` in `dashboard.cue`.
public struct GridPosition: Sendable, Codable, Hashable {
    /// Zero-based row index.
    public let row: Int
    /// Zero-based column index (0–11).
    public let col: Int
    /// Number of rows the widget occupies (>= 1).
    public let rowSpan: Int
    /// Number of columns the widget occupies (>= 1, col + colSpan <= 12).
    public let colSpan: Int

    /// Designated initialiser.
    public init(row: Int, col: Int, rowSpan: Int, colSpan: Int) {
        self.row = row
        self.col = col
        self.rowSpan = rowSpan
        self.colSpan = colSpan
    }

    /// `true` when `col + colSpan <= 12` (spec invariant §7).
    public var isWithinGridBounds: Bool { col + colSpan <= 12 }
}

// MARK: - WidgetSlot

/// Placement record binding a `widgetId` to a `GridPosition`.
///
/// Mirrors `#WidgetSlot` in `dashboard.cue`.
public struct WidgetSlot: Sendable, Codable, Hashable {
    /// References the `widgetId` of the target `AnalyticsWidget`.
    public let widgetId: String

    /// Grid placement coordinates and span.
    public let position: GridPosition

    /// Designated initialiser.
    public init(widgetId: String, position: GridPosition) {
        self.widgetId = widgetId
        self.position = position
    }
}

// MARK: - Dashboard

/// Aggregate root binding a `DashboardScope` to a curated widget layout.
///
/// One `Dashboard` exists per `(kubernetesContextId, scope)` pair in the catalog.
/// When `customisedByOperator` is `false` the dashboard is fully regenerated from
/// the matching `ScopePreset` on each application launch.
///
/// Mirrors `#Dashboard` in `dashboard.cue`.
public struct Dashboard: Sendable, Codable, Hashable {
    /// UUIDv7 — time-ordered for catalog sorting.
    public let id: String

    /// Scope discriminates which preset is used and which upstream ports are queried.
    public let scope: DashboardScope

    /// Identifies the Kubernetes context (cluster) this dashboard observes.
    /// References `kubernetesContextId` from `cluster_connectivity`.
    public let kubernetesContextId: String

    /// Ordered list of widget placements forming the current layout.
    public let layout: [WidgetSlot]

    /// Auto-refresh cadence. Effective interval doubles in macOS low-power mode.
    public let refreshInterval: RefreshInterval

    /// RFC 3339 timestamp when this dashboard record was first persisted.
    public let createdAt: String

    /// RFC 3339 timestamp of the last layout or interval mutation by the operator.
    public let updatedAt: String

    /// `true` when the operator has modified the default `ScopePreset` layout.
    /// `DashboardCompositionService` sets this flag on any layout mutation.
    public let customisedByOperator: Bool

    /// Designated initialiser.
    public init(
        id: String,
        scope: DashboardScope,
        kubernetesContextId: String,
        layout: [WidgetSlot],
        refreshInterval: RefreshInterval = .default,
        createdAt: String,
        updatedAt: String,
        customisedByOperator: Bool = false
    ) {
        self.id = id
        self.scope = scope
        self.kubernetesContextId = kubernetesContextId
        self.layout = layout
        self.refreshInterval = refreshInterval
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.customisedByOperator = customisedByOperator
    }

    /// Returns a copy with the given layout, marking `customisedByOperator = true`.
    public func withCustomLayout(_ newLayout: [WidgetSlot], updatedAt: String) -> Dashboard {
        Dashboard(
            id: id,
            scope: scope,
            kubernetesContextId: kubernetesContextId,
            layout: newLayout,
            refreshInterval: refreshInterval,
            createdAt: createdAt,
            updatedAt: updatedAt,
            customisedByOperator: true
        )
    }

    /// Returns a copy with the given refresh interval.
    public func withRefreshInterval(_ interval: RefreshInterval, updatedAt: String) -> Dashboard {
        Dashboard(
            id: id,
            scope: scope,
            kubernetesContextId: kubernetesContextId,
            layout: layout,
            refreshInterval: interval,
            createdAt: createdAt,
            updatedAt: updatedAt,
            customisedByOperator: customisedByOperator
        )
    }
}
