// Domain/TimeSeries.swift — metrics_observability bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/metrics_observability/schemas/prom_query.cue
//             (#Sample, #Point, #Series, #PromQueryResult)

import Foundation

// MARK: - MetricSample

/// One (timestamp, value) pair from an instant vector result, associated
/// with its metric label set.
///
/// Mirrors `#Sample` from `prom_query.cue`. Produced by instant queries
/// (`resultType == "vector"`).
public struct MetricSample: Hashable, Sendable, Codable {
    /// Metric labels for this sample.
    public let metric: [String: String]

    /// Unix timestamp in seconds (may be fractional).
    public let timestampUnix: Double

    /// Numeric value of the sample.
    public let value: Double

    public init(metric: [String: String], timestampUnix: Double, value: Double) {
        self.metric = metric
        self.timestampUnix = timestampUnix
        self.value = value
    }
}

// MARK: - DataPoint

/// One (timestamp, value) data point from a range matrix series.
///
/// Mirrors `#Point` from `prom_query.cue`.
public struct DataPoint: Hashable, Sendable, Codable {
    /// Unix timestamp in seconds (may be fractional).
    public let tUnix: Double

    /// Numeric value at this timestamp.
    public let value: Double

    public init(tUnix: Double, value: Double) {
        self.tUnix = tUnix
        self.value = value
    }
}

// MARK: - TimeSeries

/// One labeled time series from a range matrix result.
///
/// Mirrors `#Series` from `prom_query.cue`. Contains an ordered list of
/// `DataPoint` values. A series with more than 200 points MUST be
/// downsampled to exactly 200 before being returned to UI callers
/// (invariant — ADR-0016 §Downsampling).
public struct TimeSeries: Hashable, Sendable, Codable {
    /// Metric labels for this series.
    public let metric: [String: String]

    /// Ordered (timestamp, value) pairs. Count <= 200 after downsampling.
    public let points: [DataPoint]

    public init(metric: [String: String], points: [DataPoint]) {
        self.metric = metric
        self.points = points
    }

    /// Downsamples `points` to `targetCount` using uniform index sampling.
    ///
    /// Returns `self` unchanged when `points.count <= targetCount`.
    /// - Parameter targetCount: Target number of points. Must be >= 1.
    public func downsampled(to targetCount: Int = 200) -> TimeSeries {
        precondition(targetCount >= 1, "targetCount must be >= 1")
        guard points.count > targetCount else { return self }
        let stride = Double(points.count - 1) / Double(targetCount - 1)
        let sampled = (0..<targetCount).map { i in
            points[Int((Double(i) * stride).rounded())]
        }
        return TimeSeries(metric: metric, points: sampled)
    }
}

// MARK: - PromQueryResult

/// Discriminated union of all possible Prometheus query result shapes.
///
/// Mirrors `#PromQueryResult` from `prom_query.cue`. Returned by
/// `PrometheusQueryPort` and forwarded to UI read models without further
/// transformation except downsampling.
public enum PromQueryResult: Sendable {
    /// Instant vector (`resultType == "vector"`).
    case instantVector([MetricSample])

    /// Range matrix (`resultType == "matrix"`).
    /// Series are downsampled to <= 200 points before this value is created.
    case rangeMatrix([TimeSeries])

    /// Scalar (`resultType == "scalar"`).
    case scalar(timestampUnix: Double, value: Double)

    /// String (`resultType == "string"`).
    case string(String)
}
