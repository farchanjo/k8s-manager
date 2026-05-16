// Domain/DrawerChartCatalog.swift — app_shell bounded context
// DDD role: Domain service (compile-time catalog)
// ADR ref: ADR-0058 (detail drawer Prometheus charts)
// ADR ref: ADR-0016 (curated PromQL templates)
// ADR ref: ADR-0044 (PromQL injection prevention — anchored regex matchers)

import Foundation

// MARK: - MetricTimeRange

/// Time-range options for the drawer chart picker.
///
/// Mirrors the values required by ADR-0058 §"MetricTimeRange".
/// Cases map to concrete durations used when building `TimeRange` objects.
public enum MetricTimeRange: String, CaseIterable, Hashable, Sendable {
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case oneHour = "1h"
    case threeHours = "3h"
    case twentyFourHours = "24h"

    /// Duration in seconds.
    public var seconds: Int {
        switch self {
        case .fiveMinutes:      return 5 * 60
        case .fifteenMinutes:   return 15 * 60
        case .oneHour:          return 60 * 60
        case .threeHours:       return 3 * 60 * 60
        case .twentyFourHours:  return 24 * 60 * 60
        }
    }

    /// Preferred query step resolution capped to produce <= 200 points.
    public var stepSeconds: Int {
        max(seconds / 200, 1)
    }
}

// MARK: - MetricSeriesKey

/// Identifies a named chart series and maps to a curated PromQL template.
///
/// Keys correspond to the series defined in ADR-0058 §"PromQL templates per kind".
/// The `templateKey` drives `DrawerChartCatalog` lookups.
public enum MetricSeriesKey: String, CaseIterable, Hashable, Sendable {
    // CPU series
    case cpuUsage       = "cpu_usage"
    case cpuRequests    = "cpu_requests"
    case cpuAllocatable = "cpu_allocatable"
    case cpuCapacity    = "cpu_capacity"
    case cpuLimits      = "cpu_limits"

    // Memory series
    case memUsage       = "mem_usage"
    case memRequests    = "mem_requests"
    case memAllocatable = "mem_allocatable"
    case memCapacity    = "mem_capacity"
    case memLimits      = "mem_limits"

    // Workload overlay
    case replicasAvailable = "replicas_available"

    /// Human-readable label shown in the series picker chip.
    public var displayName: String {
        switch self {
        case .cpuUsage:       return "Usage"
        case .cpuRequests:    return "Requests"
        case .cpuAllocatable: return "Allocatable"
        case .cpuCapacity:    return "Capacity"
        case .cpuLimits:      return "Limits"
        case .memUsage:       return "Usage"
        case .memRequests:    return "Requests"
        case .memAllocatable: return "Allocatable"
        case .memCapacity:    return "Capacity"
        case .memLimits:      return "Limits"
        case .replicasAvailable: return "Replicas"
        }
    }
}

// MARK: - ChartSeriesSpec

/// Specification for a single series in the drawer chart.
///
/// The `expr` field is a PromQL template using ADR-0044 anchored label matchers
/// (`=~"^{placeholder}$"`). Placeholders are substituted at query time.
public struct ChartSeriesSpec: Hashable, Sendable {
    /// Series identifier used for picker state management.
    public let key: MetricSeriesKey
    /// PromQL expression template.
    public let expr: String
    /// True when this series belongs to the default selection for its kind.
    public let isDefaultSelected: Bool
    /// True when this series uses a secondary Y-axis (right side, integer scale).
    public let useSecondaryAxis: Bool

    public init(
        key: MetricSeriesKey,
        expr: String,
        isDefaultSelected: Bool,
        useSecondaryAxis: Bool = false
    ) {
        self.key = key
        self.expr = expr
        self.isDefaultSelected = isDefaultSelected
        self.useSecondaryAxis = useSecondaryAxis
    }
}

// MARK: - DrawerChartCatalog

/// Compile-time catalog mapping `(kind, metricGroup)` to `[ChartSeriesSpec]`.
///
/// All PromQL expressions use the anchored regex form `=~"^{value}$"` per
/// ADR-0044 to limit label matchers to the intended value. Substitution
/// placeholder validation happens in `MetricsObservabilityActor` before any
/// query is issued.
public enum DrawerChartCatalog {

    // MARK: Node — CPU

    /// Four-series CPU chart for a Node resource.
    ///
    /// Placeholders: `{node}` — validated as `^[a-zA-Z0-9._-]{1,63}$`.
    public static func nodeCPU() -> [ChartSeriesSpec] {
        [
            ChartSeriesSpec(
                key: .cpuUsage,
                expr: #"rate(node_cpu_usage_seconds_total{node=~"^{node}$",mode!="idle"}[2m])"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .cpuRequests,
                expr: #"sum(kube_pod_container_resource_requests{resource="cpu",node=~"^{node}$"})"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .cpuAllocatable,
                expr: #"kube_node_status_allocatable{resource="cpu",node=~"^{node}$"}"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .cpuCapacity,
                expr: #"kube_node_status_capacity{resource="cpu",node=~"^{node}$"}"#,
                isDefaultSelected: true
            ),
        ]
    }

    // MARK: Node — Memory

    /// Four-series memory chart for a Node resource.
    ///
    /// Placeholders: `{node}` — validated as `^[a-zA-Z0-9._-]{1,63}$`.
    public static func nodeMemory() -> [ChartSeriesSpec] {
        [
            ChartSeriesSpec(
                key: .memUsage,
                expr: #"node_memory_MemTotal_bytes{node=~"^{node}$"} - node_memory_MemAvailable_bytes{node=~"^{node}$"}"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .memRequests,
                expr: #"sum(kube_pod_container_resource_requests{resource="memory",node=~"^{node}$"})"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .memAllocatable,
                expr: #"kube_node_status_allocatable{resource="memory",node=~"^{node}$"}"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .memCapacity,
                expr: #"kube_node_status_capacity{resource="memory",node=~"^{node}$"}"#,
                isDefaultSelected: true
            ),
        ]
    }

    // MARK: Pod — CPU

    /// CPU series for a Pod resource.
    ///
    /// Placeholders: `{namespace}`, `{pod}`.
    public static func podCPU() -> [ChartSeriesSpec] {
        [
            ChartSeriesSpec(
                key: .cpuUsage,
                expr: #"rate(container_cpu_usage_seconds_total{namespace=~"^{namespace}$",pod=~"^{pod}$",container!=""}[2m])"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .cpuRequests,
                expr: #"kube_pod_container_resource_requests{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="cpu"}"#,
                isDefaultSelected: false
            ),
            ChartSeriesSpec(
                key: .cpuLimits,
                expr: #"kube_pod_container_resource_limits{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="cpu"}"#,
                isDefaultSelected: false
            ),
        ]
    }

    // MARK: Pod — Memory

    /// Memory series for a Pod resource.
    ///
    /// Placeholders: `{namespace}`, `{pod}`.
    public static func podMemory() -> [ChartSeriesSpec] {
        [
            ChartSeriesSpec(
                key: .memUsage,
                expr: #"container_memory_working_set_bytes{namespace=~"^{namespace}$",pod=~"^{pod}$",container!=""}"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .memRequests,
                expr: #"kube_pod_container_resource_requests{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="memory"}"#,
                isDefaultSelected: false
            ),
            ChartSeriesSpec(
                key: .memLimits,
                expr: #"kube_pod_container_resource_limits{namespace=~"^{namespace}$",pod=~"^{pod}$",resource="memory"}"#,
                isDefaultSelected: false
            ),
        ]
    }

    // MARK: Workload (Deployment / StatefulSet / DaemonSet)

    /// Aggregate CPU series for Deployment workloads.
    ///
    /// Placeholders: `{namespace}`, `{workload}`.
    public static func deploymentCPU() -> [ChartSeriesSpec] {
        [
            ChartSeriesSpec(
                key: .cpuUsage,
                expr: #"sum(rate(container_cpu_usage_seconds_total{namespace=~"^{namespace}$"}[2m]))"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .replicasAvailable,
                expr: #"kube_deployment_status_replicas_available{namespace=~"^{namespace}$",deployment=~"^{workload}$"}"#,
                isDefaultSelected: true,
                useSecondaryAxis: true
            ),
        ]
    }

    /// Aggregate CPU series for StatefulSet workloads.
    public static func statefulSetCPU() -> [ChartSeriesSpec] {
        [
            ChartSeriesSpec(
                key: .cpuUsage,
                expr: #"sum(rate(container_cpu_usage_seconds_total{namespace=~"^{namespace}$"}[2m]))"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .replicasAvailable,
                expr: #"kube_statefulset_status_replicas_ready{namespace=~"^{namespace}$",statefulset=~"^{workload}$"}"#,
                isDefaultSelected: true,
                useSecondaryAxis: true
            ),
        ]
    }

    /// Aggregate CPU series for DaemonSet workloads.
    public static func daemonSetCPU() -> [ChartSeriesSpec] {
        [
            ChartSeriesSpec(
                key: .cpuUsage,
                expr: #"sum(rate(container_cpu_usage_seconds_total{namespace=~"^{namespace}$"}[2m]))"#,
                isDefaultSelected: true
            ),
            ChartSeriesSpec(
                key: .replicasAvailable,
                expr: #"kube_daemonset_status_number_ready{namespace=~"^{namespace}$",daemonset=~"^{workload}$"}"#,
                isDefaultSelected: true,
                useSecondaryAxis: true
            ),
        ]
    }

    // MARK: Kind lookup

    /// Returns the CPU series specs for `kind`.
    ///
    /// Returns an empty array for kinds without a curated CPU chart.
    public static func cpuSeries(for kind: String) -> [ChartSeriesSpec] {
        switch kind {
        case "Node":        return nodeCPU()
        case "Pod":         return podCPU()
        case "Deployment":  return deploymentCPU()
        case "StatefulSet": return statefulSetCPU()
        case "DaemonSet":   return daemonSetCPU()
        default:            return []
        }
    }

    /// Returns the memory series specs for `kind`.
    ///
    /// Returns an empty array for kinds without a curated memory chart.
    public static func memorySeries(for kind: String) -> [ChartSeriesSpec] {
        switch kind {
        case "Node": return nodeMemory()
        case "Pod":  return podMemory()
        default:     return []
        }
    }

    /// Default series key selection for `kind`.
    ///
    /// Nodes: all four CPU series selected.
    /// Pod and workload kinds: Usage only.
    public static func defaultSelection(for kind: String) -> Set<MetricSeriesKey> {
        switch kind {
        case "Node":
            return [.cpuUsage, .cpuRequests, .cpuAllocatable, .cpuCapacity]
        default:
            return [.cpuUsage, .memUsage]
        }
    }
}
