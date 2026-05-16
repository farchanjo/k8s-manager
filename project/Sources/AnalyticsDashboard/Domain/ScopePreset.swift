// Domain/ScopePreset.swift — analytics_dashboard bounded context
// DDD role: ValueObject (immutable application preset)
// Spec:      docs/arch/contexts/analytics_dashboard/schemas/scope_preset.cue
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Swift 6 strict concurrency — all types are value types conforming to Sendable.

import Foundation

// MARK: - ScopePreset

/// Immutable default widget layout for one `DashboardScope` variant.
///
/// Ships with the application. `DashboardCompositionService` loads the matching
/// preset when an operator selects a scope for the first time and
/// `Dashboard.customisedByOperator == false`.
///
/// Mirrors `#ScopePreset` in `scope_preset.cue`.
public struct ScopePreset: Sendable, Codable, Hashable {
    /// Stable kebab-case slug matching the `scopeKind` of the corresponding
    /// `DashboardScope` variant.
    public let presetId: String

    /// Human-readable display name shown in the scope picker.
    public let label: String

    /// Ordered default widget placements forming the 12-column grid layout.
    public let defaultLayout: [WidgetSlot]

    /// Designated initialiser.
    public init(presetId: String, label: String, defaultLayout: [WidgetSlot]) {
        self.presetId = presetId
        self.label = label
        self.defaultLayout = defaultLayout
    }
}

// MARK: - Built-in presets

extension ScopePreset {
    /// All built-in presets shipped with the application.
    ///
    /// Mirrors every `#*Preset` concrete value in `scope_preset.cue`.
    public static let all: [ScopePreset] = [
        clusterOverview,
        namespaceDetail,
        podDetail,
        nodeDetail,
        workloadDetail,
        serviceDetail,
        helmReleaseDetail,
        debugTimeline,
        topologyGraph
    ]

    /// Returns the preset matching the given `DashboardScope`, or `nil` if none is found.
    public static func preset(for scope: DashboardScope) -> ScopePreset? {
        all.first { $0.presetId == scope.presetId }
    }

    // MARK: ClusterOverview

    /// Default layout for `ClusterOverviewScope`.
    public static let clusterOverview = ScopePreset(
        presetId: "cluster_overview",
        label: "Cluster Overview",
        defaultLayout: [
            WidgetSlot(widgetId: "nodes-ready-count",       position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "pods-phase-stacked-bar",  position: GridPosition(row: 0, col: 3, rowSpan: 1, colSpan: 5)),
            WidgetSlot(widgetId: "namespace-count",         position: GridPosition(row: 0, col: 8, rowSpan: 1, colSpan: 2)),
            WidgetSlot(widgetId: "deployments-available",   position: GridPosition(row: 0, col: 10, rowSpan: 1, colSpan: 2)),
            WidgetSlot(widgetId: "cluster-cpu-sparkline",   position: GridPosition(row: 1, col: 0, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "cluster-mem-sparkline",   position: GridPosition(row: 1, col: 6, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "top-namespaces-cpu",      position: GridPosition(row: 2, col: 0, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "top-namespaces-mem",      position: GridPosition(row: 2, col: 6, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "recent-cluster-events",   position: GridPosition(row: 4, col: 0, rowSpan: 2, colSpan: 12)),
        ]
    )

    // MARK: NamespaceDetail

    /// Default layout for `NamespaceDetailScope`.
    public static let namespaceDetail = ScopePreset(
        presetId: "namespace_detail",
        label: "Namespace Detail",
        defaultLayout: [
            WidgetSlot(widgetId: "workload-kind-stacked-bar",   position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "ns-pods-phase-stacked-bar",   position: GridPosition(row: 0, col: 6, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "ns-cpu-requests-limits",      position: GridPosition(row: 1, col: 0, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "ns-mem-requests-limits",      position: GridPosition(row: 1, col: 6, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "ns-network-in-sparkline",     position: GridPosition(row: 3, col: 0, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "ns-network-out-sparkline",    position: GridPosition(row: 3, col: 6, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "top-pods-cpu",                position: GridPosition(row: 4, col: 0, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "top-pods-mem",                position: GridPosition(row: 4, col: 6, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "ns-recent-events",            position: GridPosition(row: 6, col: 0, rowSpan: 2, colSpan: 12)),
        ]
    )

    // MARK: PodDetail

    /// Default layout for `PodDetailScope` (USE method: utilization → saturation → errors).
    public static let podDetail = ScopePreset(
        presetId: "pod_detail",
        label: "Pod Detail",
        defaultLayout: [
            WidgetSlot(widgetId: "pod-cpu-line-chart",       position: GridPosition(row: 0, col: 0, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "pod-mem-line-chart",       position: GridPosition(row: 0, col: 6, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "pod-restart-count",        position: GridPosition(row: 2, col: 0, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "pod-log-error-rate",       position: GridPosition(row: 2, col: 3, rowSpan: 1, colSpan: 5)),
            WidgetSlot(widgetId: "pod-oomkilled-count",      position: GridPosition(row: 2, col: 8, rowSpan: 1, colSpan: 4)),
            WidgetSlot(widgetId: "pod-net-rx-sparkline",     position: GridPosition(row: 3, col: 0, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "pod-net-tx-sparkline",     position: GridPosition(row: 3, col: 6, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "pod-disk-read-sparkline",  position: GridPosition(row: 4, col: 0, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "pod-disk-write-sparkline", position: GridPosition(row: 4, col: 6, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "pod-events-timeline",      position: GridPosition(row: 5, col: 0, rowSpan: 2, colSpan: 12)),
        ]
    )

    // MARK: NodeDetail

    /// Default layout for `NodeDetailScope` (USE method).
    public static let nodeDetail = ScopePreset(
        presetId: "node_detail",
        label: "Node Detail",
        defaultLayout: [
            WidgetSlot(widgetId: "node-conditions-list",         position: GridPosition(row: 0, col: 0, rowSpan: 2, colSpan: 4)),
            WidgetSlot(widgetId: "node-pod-density-count",       position: GridPosition(row: 0, col: 4, rowSpan: 1, colSpan: 4)),
            WidgetSlot(widgetId: "node-capacity-allocatable",    position: GridPosition(row: 0, col: 8, rowSpan: 1, colSpan: 4)),
            WidgetSlot(widgetId: "node-cpu-line-chart",          position: GridPosition(row: 2, col: 0, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "node-mem-line-chart",          position: GridPosition(row: 2, col: 6, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "node-disk-pressure-sparkline", position: GridPosition(row: 4, col: 0, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "node-image-gc-sparkline",      position: GridPosition(row: 4, col: 6, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "node-top-pods-cpu",            position: GridPosition(row: 5, col: 0, rowSpan: 2, colSpan: 6)),
            WidgetSlot(widgetId: "node-top-pods-mem",            position: GridPosition(row: 5, col: 6, rowSpan: 2, colSpan: 6)),
        ]
    )

    // MARK: WorkloadDetail

    /// Default layout for `WorkloadDetailScope`.
    public static let workloadDetail = ScopePreset(
        presetId: "workload_detail",
        label: "Workload Detail",
        defaultLayout: [
            WidgetSlot(widgetId: "workload-replicas-desired",    position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "workload-replicas-available",  position: GridPosition(row: 0, col: 3, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "workload-rollout-progress",    position: GridPosition(row: 0, col: 6, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "workload-replicas-line-chart", position: GridPosition(row: 1, col: 0, rowSpan: 2, colSpan: 8)),
            WidgetSlot(widgetId: "workload-pod-restart-rate",    position: GridPosition(row: 1, col: 8, rowSpan: 2, colSpan: 4)),
            WidgetSlot(widgetId: "workload-rollout-events",      position: GridPosition(row: 3, col: 0, rowSpan: 2, colSpan: 12)),
        ]
    )

    // MARK: ServiceDetail (RED method)

    /// Default layout for `ServiceDetailScope` — RED method: rate | error rate | latency.
    public static let serviceDetail = ScopePreset(
        presetId: "service_detail",
        label: "Service Detail",
        defaultLayout: [
            WidgetSlot(widgetId: "svc-endpoints-count",          position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "svc-selector-match-count",     position: GridPosition(row: 0, col: 3, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "svc-error-rate-count",         position: GridPosition(row: 0, col: 6, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "svc-p99-latency-count",        position: GridPosition(row: 0, col: 9, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "svc-request-rate-line-chart",  position: GridPosition(row: 1, col: 0, rowSpan: 2, colSpan: 4)),
            WidgetSlot(widgetId: "svc-error-rate-line-chart",    position: GridPosition(row: 1, col: 4, rowSpan: 2, colSpan: 4)),
            WidgetSlot(widgetId: "svc-latency-heatmap",          position: GridPosition(row: 1, col: 8, rowSpan: 4, colSpan: 4)),
            WidgetSlot(widgetId: "svc-rps-sparkline",            position: GridPosition(row: 3, col: 0, rowSpan: 1, colSpan: 4)),
            WidgetSlot(widgetId: "svc-error-sparkline",          position: GridPosition(row: 3, col: 4, rowSpan: 1, colSpan: 4)),
        ]
    )

    // MARK: HelmReleaseDetail

    /// Default layout for `HelmReleaseDetailScope`.
    public static let helmReleaseDetail = ScopePreset(
        presetId: "helm_release_detail",
        label: "Helm Release Detail",
        defaultLayout: [
            WidgetSlot(widgetId: "helm-revision-count",   position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "helm-hook-outcomes",    position: GridPosition(row: 0, col: 3, rowSpan: 1, colSpan: 9)),
            WidgetSlot(widgetId: "helm-manifest-diff",    position: GridPosition(row: 1, col: 0, rowSpan: 6, colSpan: 12)),
            WidgetSlot(widgetId: "helm-release-events",   position: GridPosition(row: 7, col: 0, rowSpan: 2, colSpan: 12)),
        ]
    )

    // MARK: DebugTimeline

    /// Default layout for `DebugTimelineScope`.
    public static let debugTimeline = ScopePreset(
        presetId: "debug_timeline",
        label: "Debug Timeline",
        defaultLayout: [
            WidgetSlot(widgetId: "debug-k8s-event-count",    position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 4)),
            WidgetSlot(widgetId: "debug-mutation-count",     position: GridPosition(row: 0, col: 4, rowSpan: 1, colSpan: 4)),
            WidgetSlot(widgetId: "debug-tool-call-count",    position: GridPosition(row: 0, col: 8, rowSpan: 1, colSpan: 4)),
            WidgetSlot(widgetId: "debug-unified-timeline",   position: GridPosition(row: 1, col: 0, rowSpan: 8, colSpan: 12)),
        ]
    )

    // MARK: TopologyGraph

    /// Default layout for `TopologyGraphScope`.
    public static let topologyGraph = ScopePreset(
        presetId: "topology_graph",
        label: "Topology Graph",
        defaultLayout: [
            WidgetSlot(widgetId: "topo-node-count",            position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "topo-edge-count",            position: GridPosition(row: 0, col: 3, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "topo-helm-release-count",    position: GridPosition(row: 0, col: 6, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "topo-service-count",         position: GridPosition(row: 0, col: 9, rowSpan: 1, colSpan: 3)),
            WidgetSlot(widgetId: "topo-graph-widget",          position: GridPosition(row: 1, col: 0, rowSpan: 10, colSpan: 12)),
        ]
    )
}
