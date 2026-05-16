// Domain/PromQuery.swift — metrics_observability bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/metrics_observability/schemas/prom_query.cue

import Foundation

// MARK: - TimeRange

/// Time window for a range query.
///
/// Mirrors `#TimeRange` from `prom_query.cue`. Both timestamps are RFC 3339
/// strings; `stepSeconds` must be at least 1 second.
public struct TimeRange: Hashable, Sendable, Codable {
    /// RFC 3339 start timestamp.
    public let start: String

    /// RFC 3339 end timestamp.
    public let end: String

    /// Query resolution step in seconds. Minimum 1.
    public let stepSeconds: Int

    public init(start: String, end: String, stepSeconds: Int) {
        precondition(stepSeconds >= 1, "stepSeconds must be >= 1")
        self.start = start
        self.end = end
        self.stepSeconds = stepSeconds
    }
}

// MARK: - PromQuery

/// Immutable description of a single PromQL query request.
///
/// Mirrors `#PromQuery` from `prom_query.cue`. Exactly one of
/// `instant == true` or `range != nil` must hold; the initialiser enforces
/// this invariant.
public struct PromQuery: Hashable, Sendable, Codable {
    /// PromQL expression to evaluate. Must be non-empty.
    public let expr: String

    /// When `true`, the query targets `/api/v1/query` (instant vector).
    /// When `false`, a `range` must be supplied.
    public let instant: Bool

    /// Range definition. Required when `instant == false`.
    public let range: TimeRange?

    /// Optional label selector to restrict query scope.
    /// Keys and values are plain strings appended as additional label matchers.
    public let labelSelector: [String: String]?

    /// Creates an instant query.
    ///
    /// - Parameters:
    ///   - expr: Non-empty PromQL expression.
    ///   - labelSelector: Optional label matchers.
    public static func instant(
        expr: String,
        labelSelector: [String: String]? = nil
    ) -> PromQuery {
        precondition(!expr.isEmpty, "expr must not be empty")
        return PromQuery(expr: expr, instant: true, range: nil, labelSelector: labelSelector)
    }

    /// Creates a range query.
    ///
    /// - Parameters:
    ///   - expr: Non-empty PromQL expression.
    ///   - range: Time window and step resolution.
    ///   - labelSelector: Optional label matchers.
    public static func range(
        expr: String,
        range: TimeRange,
        labelSelector: [String: String]? = nil
    ) -> PromQuery {
        precondition(!expr.isEmpty, "expr must not be empty")
        return PromQuery(expr: expr, instant: false, range: range, labelSelector: labelSelector)
    }

    private init(
        expr: String,
        instant: Bool,
        range: TimeRange?,
        labelSelector: [String: String]?
    ) {
        self.expr = expr
        self.instant = instant
        self.range = range
        self.labelSelector = labelSelector
    }
}
