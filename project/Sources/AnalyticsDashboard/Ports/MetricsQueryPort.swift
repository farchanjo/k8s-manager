// Ports/MetricsQueryPort.swift — analytics_dashboard bounded context
// DDD role: Port (outbound — consumes metrics_observability)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Ports
// ADR ref:   ADR-0024, ADR-0016 (PromQL execution), ADR-0044 (injection prevention)
//
// Used by WidgetQueryDispatchService to execute PromQL range and instant queries
// for Sparkline, LineChart, Heatmap, Count, TopList, and LogErrorRate widgets.

import Foundation

// MARK: - MetricDataPoint

/// A single (timestamp, value) pair in a metric series.
public struct MetricDataPoint: Sendable, Codable, Hashable {
    /// Unix timestamp in seconds (fractional for sub-second precision).
    public let tUnix: Double
    /// Metric value at this timestamp.
    public let value: Double

    /// Designated initialiser.
    public init(tUnix: Double, value: Double) {
        self.tUnix = tUnix
        self.value = value
    }
}

// MARK: - MetricSeries

/// A labeled time series of `MetricDataPoint` values.
public struct MetricSeries: Sendable, Codable, Hashable {
    /// Prometheus label set for this series (e.g., `["__name__": "up", "job": "k8s"]`).
    public let labels: [String: String]
    /// Ordered time-series data points.
    public let points: [MetricDataPoint]

    /// Designated initialiser.
    public init(labels: [String: String], points: [MetricDataPoint]) {
        self.labels = labels
        self.points = points
    }
}

// MARK: - InstantSample

/// A single metric sample returned by an instant-vector query.
public struct InstantSample: Sendable, Codable, Hashable {
    /// Prometheus label set.
    public let labels: [String: String]
    /// Sample timestamp.
    public let tUnix: Double
    /// Sample value.
    public let value: Double

    /// Designated initialiser.
    public init(labels: [String: String], tUnix: Double, value: Double) {
        self.labels = labels
        self.tUnix = tUnix
        self.value = value
    }
}

// MARK: - MetricsQueryPort

/// Executes PromQL instant and range queries against `metrics_observability`.
///
/// `WidgetQueryDispatchService` consumes this port to feed Sparkline, LineChart,
/// Heatmap, Count, TopList, and LogErrorRate widgets.
///
/// Scope parameter substitution (replacing `{namespace}`, `{pod}`, `{node}`,
/// `{service}`, etc. in PromQL templates) is done by the caller before invoking
/// this port; the port receives fully-resolved expressions.
///
/// Range query results are downsampled to at most 200 points before being
/// returned (invariant — ADR-0016 §Downsampling).
public protocol MetricsQueryPort: Sendable {
    /// Executes a PromQL instant-vector query.
    ///
    /// - Parameters:
    ///   - promQL: Fully-resolved PromQL expression (no unsubstituted placeholders).
    ///   - kubernetesContextId: Identifies the cluster whose Prometheus endpoint is used.
    /// - Returns: Ordered list of `InstantSample` values.
    /// - Throws: `MetricsQueryError` on transport or decode failure.
    func instantQuery(
        promQL: String,
        kubernetesContextId: String
    ) async throws -> [InstantSample]

    /// Executes a PromQL range query.
    ///
    /// - Parameters:
    ///   - promQL: Fully-resolved PromQL expression.
    ///   - rangeMinutes: Look-back window in minutes from now.
    ///   - kubernetesContextId: Identifies the cluster whose Prometheus endpoint is used.
    /// - Returns: List of labeled time series, each downsampled to <= 200 points.
    /// - Throws: `MetricsQueryError` on transport or decode failure.
    func rangeQuery(
        promQL: String,
        rangeMinutes: Int,
        kubernetesContextId: String
    ) async throws -> [MetricSeries]
}

// MARK: - MetricsQueryError

/// Errors raised by `MetricsQueryPort` implementations.
public enum MetricsQueryError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// Network or TLS failure before a response was received.
    case transportError(detail: String)
    /// The endpoint returned an unexpected HTTP status.
    case unexpectedStatus(code: Int, detail: String)
    /// The response body could not be decoded.
    case decodeError(detail: String)
    /// Request timed out.
    case timeout
    /// No Prometheus endpoint is configured for the given context.
    case noEndpointConfigured(contextId: String)
}

// MARK: - UnimplementedMetricsQueryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` until an adapter registers.
public struct UnimplementedMetricsQueryPort: MetricsQueryPort {
    public init() {}

    public func instantQuery(promQL _: String, kubernetesContextId _: String) async throws -> [InstantSample] {
        throw MetricsQueryError.unimplemented
    }

    public func rangeQuery(
        promQL _: String,
        rangeMinutes _: Int,
        kubernetesContextId _: String
    ) async throws -> [MetricSeries] {
        throw MetricsQueryError.unimplemented
    }
}
