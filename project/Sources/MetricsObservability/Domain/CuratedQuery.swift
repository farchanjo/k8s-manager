// Domain/CuratedQuery.swift — metrics_observability bounded context
// DDD role: ValueObject (compile-time catalog entry)
// CUE source: docs/arch/contexts/metrics_observability/schemas/curated_query_set.cue

import Foundation

// MARK: - QueryCategory

/// Functional category for grouping curated queries in the UI.
///
/// Mirrors the `category` field of `#CuratedQuery` from `curated_query_set.cue`.
public enum QueryCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case cpu
    case memory
    case network
    case disk
    case apiServer = "api_server"
    case workloadHealth = "workload_health"
}

// MARK: - DefaultRange

/// Default time-range template applied when the operator has not customised
/// the window.
///
/// `start` and `end` use "now-{offset}" notation; the client substitutes
/// concrete RFC 3339 values at render time.
public struct DefaultRange: Hashable, Sendable, Codable {
    public let start: String
    public let end: String
    public let stepSeconds: Int

    public init(start: String, end: String, stepSeconds: Int) {
        precondition(stepSeconds >= 1, "stepSeconds must be >= 1")
        self.start = start
        self.end = end
        self.stepSeconds = stepSeconds
    }
}

// MARK: - CuratedQuery

/// Immutable compile-time PromQL template entry.
///
/// Mirrors `#CuratedQuery` from `curated_query_set.cue`. Placeholders in
/// `expr` use curly-brace notation: `{namespace}`, `{podName}`, `{node}`.
/// Templates are resolved at query time; the entry itself is never mutated.
public struct CuratedQuery: Hashable, Sendable, Codable {
    /// Unique slug identifier (lowercase, underscores).
    public let id: String

    /// Human-readable display name for the UI.
    public let name: String

    /// PromQL expression template. May contain placeholders.
    public let expr: String

    /// Functional category.
    public let category: QueryCategory

    /// Default time-range template.
    public let defaultRange: DefaultRange

    /// Default resolution step in seconds.
    public let defaultStepSeconds: Int

    public init(
        id: String,
        name: String,
        expr: String,
        category: QueryCategory,
        defaultRange: DefaultRange,
        defaultStepSeconds: Int
    ) {
        precondition(!id.isEmpty, "id must not be empty")
        precondition(!name.isEmpty, "name must not be empty")
        precondition(!expr.isEmpty, "expr must not be empty")
        precondition(defaultStepSeconds >= 1, "defaultStepSeconds must be >= 1")
        self.id = id
        self.name = name
        self.expr = expr
        self.category = category
        self.defaultRange = defaultRange
        self.defaultStepSeconds = defaultStepSeconds
    }
}

// MARK: - CuratedQueryCatalog

/// Compile-time catalog of all curated PromQL templates shipped with the app.
///
/// The catalog is a value-type constant; no runtime mutation is permitted.
/// Mirrors `#CuratedQueryCatalog` from `curated_query_set.cue`.
public enum CuratedQueryCatalog {
    /// The ordered list of 12 curated query entries.
    public static let all: [CuratedQuery] = [
        // MARK: CPU
        CuratedQuery(
            id: "pod_cpu_usage_seconds",
            name: "Pod CPU Usage (rate 2m)",
            expr: #"rate(container_cpu_usage_seconds_total{namespace="{namespace}",pod=~"{podName}",container!=""}[2m])"#,
            category: .cpu,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),
        CuratedQuery(
            id: "node_cpu_busy_percent",
            name: "Node CPU Busy %",
            expr: #"1 - avg(rate(node_cpu_seconds_total{mode="idle",node="{node}"}[2m]))"#,
            category: .cpu,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),

        // MARK: Memory
        CuratedQuery(
            id: "pod_memory_working_set_bytes",
            name: "Pod Memory Working Set",
            expr: #"container_memory_working_set_bytes{namespace="{namespace}",pod=~"{podName}",container!=""}"#,
            category: .memory,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),
        CuratedQuery(
            id: "node_memory_available_bytes",
            name: "Node Memory Available",
            expr: #"node_memory_MemAvailable_bytes{node="{node}"}"#,
            category: .memory,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),

        // MARK: Network
        CuratedQuery(
            id: "pod_network_rx_bytes_rate",
            name: "Pod Network Receive Rate",
            expr: #"rate(container_network_receive_bytes_total{namespace="{namespace}",pod=~"{podName}"}[2m])"#,
            category: .network,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),
        CuratedQuery(
            id: "pod_network_tx_bytes_rate",
            name: "Pod Network Transmit Rate",
            expr: #"rate(container_network_transmit_bytes_total{namespace="{namespace}",pod=~"{podName}"}[2m])"#,
            category: .network,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),

        // MARK: Disk
        CuratedQuery(
            id: "node_disk_io_utilization",
            name: "Node Disk I/O Utilization",
            expr: #"rate(node_disk_io_time_seconds_total{node="{node}"}[2m])"#,
            category: .disk,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),

        // MARK: API Server
        CuratedQuery(
            id: "apiserver_request_rate",
            name: "API Server Request Rate",
            expr: "rate(apiserver_request_total[1m])",
            category: .apiServer,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),
        CuratedQuery(
            id: "apiserver_5xx_rate",
            name: "API Server 5xx Error Rate",
            expr: #"rate(apiserver_request_total{code=~"5.."}[1m])"#,
            category: .apiServer,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),
        CuratedQuery(
            id: "apiserver_p99_latency",
            name: "API Server P99 Latency (s)",
            expr: "histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket[5m])) by (le))",
            category: .apiServer,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),

        // MARK: Workload Health
        CuratedQuery(
            id: "workload_replicas_available",
            name: "Workload Available Replicas",
            expr: #"kube_deployment_status_replicas_available{namespace="{namespace}"} or kube_statefulset_replicas{namespace="{namespace}"}"#,
            category: .workloadHealth,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),
        CuratedQuery(
            id: "workload_restart_rate",
            name: "Container Restart Rate (15m)",
            expr: #"rate(kube_pod_container_status_restarts_total{namespace="{namespace}"}[15m])"#,
            category: .workloadHealth,
            defaultRange: DefaultRange(start: "now-60m", end: "now", stepSeconds: 30),
            defaultStepSeconds: 30
        ),
    ]
}
