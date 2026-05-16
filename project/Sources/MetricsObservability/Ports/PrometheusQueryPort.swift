// Ports/PrometheusQueryPort.swift — metrics_observability bounded context
// DDD role: Port (primary — outbound to Prometheus HTTP API)
// ADR ref: ADR-0016 (HTTP client strategy, curated queries, caching)
// ADR ref: ADR-0044 (PromQL injection prevention)

import Foundation

// MARK: - PrometheusQueryPort

/// Executes PromQL queries against a Prometheus HTTP API endpoint.
///
/// Declared in the domain core; implemented by `PrometheusQueryAdapter` in
/// infrastructure. The domain core never imports `URLSession` directly —
/// that coupling lives in the adapter.
///
/// Range query results are downsampled to at most 200 points before being
/// returned (invariant — ADR-0016 §Downsampling). Instant query results
/// are returned verbatim.
public protocol PrometheusQueryPort: Sendable {
    /// Executes a PromQL instant query (`/api/v1/query`).
    ///
    /// - Parameters:
    ///   - query: The PromQL query. Must satisfy `query.instant == true`.
    ///   - endpoint: The Prometheus endpoint to target.
    /// - Returns: An instant-vector `PromQueryResult`.
    /// - Throws: `PrometheusQueryError` on transport or decode failure.
    func instantQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult

    /// Executes a PromQL range query (`/api/v1/query_range`).
    ///
    /// Series are downsampled to <= 200 points before the result is returned.
    ///
    /// - Parameters:
    ///   - query: The PromQL query. Must satisfy `query.instant == false`
    ///     and `query.range != nil`.
    ///   - endpoint: The Prometheus endpoint to target.
    /// - Returns: A range-matrix `PromQueryResult`.
    /// - Throws: `PrometheusQueryError` on transport or decode failure.
    func rangeQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult
}

// MARK: - PrometheusQueryError

/// Errors raised by `PrometheusQueryPort` implementations.
public enum PrometheusQueryError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// Network or TLS failure before a response was received.
    case transportError(detail: String)

    /// The endpoint returned an unexpected HTTP status.
    case unexpectedStatus(code: Int, detail: String)

    /// The response body could not be decoded.
    case decodeError(detail: String)

    /// Request timed out (30-second limit per ADR-0016).
    case timeout

    /// The endpoint returned HTTP 401; bearer token may be stale.
    case unauthorized

    /// A substitution value failed the injection-guard regex
    /// (`^[a-zA-Z0-9._-]{1,63}$` — ADR-0044).
    case invalidParameter(value: String, template: String)

    /// The Prometheus API returned a result type the client does not handle.
    case unsupportedResultType(String)
}

// MARK: - UnimplementedPrometheusQueryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedPrometheusQueryPort: PrometheusQueryPort {
    public init() {}

    public func instantQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        throw PrometheusQueryError.unimplemented
    }

    public func rangeQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        throw PrometheusQueryError.unimplemented
    }
}
