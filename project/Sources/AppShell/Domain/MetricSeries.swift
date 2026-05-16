// Domain/MetricSeries.swift — app_shell bounded context
// DDD role: ValueObject — metric data for per-row mini-bars
// ADR ref: ADR-0059 (resource list row metric mini-bars)

import Foundation

// MARK: - MetricDimension

/// The metric dimension shown as a mini-bar per ADR-0059.
public enum MetricDimension: String, Sendable, Hashable, CaseIterable {
    /// CPU usage relative to allocatable or requested capacity.
    case cpu
    /// Memory (working set) usage relative to allocatable or requested capacity.
    case memory
    /// Disk I/O utilisation as a fraction (0–1). Prometheus-only; no kubelet fallback.
    case disk

    /// Short label for the VoiceOver accessibility description.
    public var displayLabel: String {
        switch self {
        case .cpu:    return "CPU"
        case .memory: return "Memory"
        case .disk:   return "Disk"
        }
    }
}

// MARK: - MetricDataState

/// Lifecycle state of a metric sample for a single row.
public enum MetricDataState: Sendable, Hashable {
    /// Metric data is available with current value and capacity.
    case available(value: Double, capacity: Double)
    /// No capacity request is set; the bar renders at zero with a tooltip.
    case noRequestSet
    /// Prometheus endpoint is not reachable and the kubelet fallback does not cover this dimension.
    case unavailable
    /// Cluster is disconnected; the last-known value is preserved but rendered in grey.
    case frozen(value: Double, capacity: Double)
}

// MARK: - MetricSeries

/// Resolved metric data for a single resource row and metric dimension.
///
/// `MetricSeries` is the value object passed from the view-model layer into
/// `MetricMiniBar`. It carries the dimension, data state, and the optional
/// tooltip message shown on hover.
public struct MetricSeries: Sendable, Hashable {
    /// Metric dimension (CPU / Memory / Disk).
    public let dimension: MetricDimension
    /// Current data state.
    public let state: MetricDataState

    public init(dimension: MetricDimension, state: MetricDataState) {
        self.dimension = dimension
        self.state = state
    }

    // MARK: Convenience factories

    /// Creates an available metric series with the given current and capacity values.
    public static func available(
        dimension: MetricDimension,
        value: Double,
        capacity: Double
    ) -> MetricSeries {
        .init(dimension: dimension, state: .available(value: value, capacity: capacity))
    }

    /// Creates a frozen metric series (cluster disconnected).
    public static func frozen(
        dimension: MetricDimension,
        value: Double,
        capacity: Double
    ) -> MetricSeries {
        .init(dimension: dimension, state: .frozen(value: value, capacity: capacity))
    }

    /// Creates an unavailable metric series (Prometheus unreachable, no kubelet fallback).
    public static func unavailable(dimension: MetricDimension) -> MetricSeries {
        .init(dimension: dimension, state: .unavailable)
    }

    // MARK: Computed

    /// Fill ratio clamped to `[0.0, 1.0]`.
    ///
    /// Returns `0.0` when the state is `.unavailable`, `.noRequestSet`,
    /// or when `capacity <= 0`.
    public var fillRatio: Double {
        switch state {
        case .available(let value, let capacity) where capacity > 0:
            return max(0.0, min(1.0, value / capacity))
        case .frozen(let value, let capacity) where capacity > 0:
            return max(0.0, min(1.0, value / capacity))
        default:
            return 0.0
        }
    }

    /// Accessibility description including the metric name and percentage.
    ///
    /// Format: `"CPU 42 percent"`, `"Memory unavailable"`, etc.
    public var accessibilityLabel: String {
        let label = dimension.displayLabel
        switch state {
        case .available, .frozen:
            let pct = Int(fillRatio * 100)
            return "\(label) \(pct) percent"
        case .unavailable:
            return "\(label) unavailable"
        case .noRequestSet:
            return "\(label) no request set"
        }
    }

    /// Hover tooltip text shown by `MetricMiniBar`.
    public var tooltip: String {
        switch state {
        case .available(let value, let capacity):
            return "\(dimension.displayLabel): \(formatValue(value)) / \(formatValue(capacity))"
        case .frozen(let value, let capacity):
            return "\(dimension.displayLabel): \(formatValue(value)) / \(formatValue(capacity)) (cluster disconnected — metrics frozen)"
        case .unavailable:
            return dimension == .disk
                ? "disk unavailable without Prometheus"
                : "metrics unavailable"
        case .noRequestSet:
            return "no request set"
        }
    }

    // MARK: Private

    private func formatValue(_ v: Double) -> String {
        v.formatted(.number.precision(.significantDigits(2)))
    }
}

// MARK: - RowMetricFeedPort

/// Port contract for feeding metric data into a resource list row.
///
/// Concrete adapters (Prometheus, kubelet proxy) live in composition root and
/// are injected via the `Dependencies` library. The port is never imported
/// by infrastructure modules.
public protocol RowMetricFeedPort: Sendable {
    /// Returns the current metric series for a node identified by name.
    func metrics(forNode nodeName: String) async -> [MetricSeries]
    /// Returns the current metric series for a pod identified by namespace + name.
    func metrics(forPodNamespace ns: String, name: String) async -> [MetricSeries]
}

// MARK: - StubRowMetricFeedAdapter

/// No-op adapter used when no Prometheus or kubelet endpoint is configured.
///
/// All rows return `.unavailable` series so `MetricMiniBar` renders greyed bars
/// with the appropriate tooltip rather than hiding entirely.
public struct StubRowMetricFeedAdapter: RowMetricFeedPort, Sendable {
    public init() {}

    public func metrics(forNode _: String) async -> [MetricSeries] {
        MetricDimension.allCases.map { MetricSeries.unavailable(dimension: $0) }
    }

    public func metrics(forPodNamespace _: String, name _: String) async -> [MetricSeries] {
        [.unavailable(dimension: .cpu), .unavailable(dimension: .memory)]
    }
}
