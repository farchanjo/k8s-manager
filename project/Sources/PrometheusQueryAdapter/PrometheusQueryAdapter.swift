// PrometheusQueryAdapter.swift — infrastructure adapter
// Implements: PrometheusQueryPort from MetricsObservability
// Library: swift-server/async-http-client (Tier A per ADR-0019)
// ADR ref: ADR-0016 (HTTP client strategy, curated queries)
// ADR ref: ADR-0044 (PromQL injection prevention)

import AsyncHTTPClient
import Foundation
import MetricsObservability

// MARK: - PrometheusQueryAdapter

/// Module-level factory for the Prometheus query adapter.
///
/// The composition root calls `makePort(httpClient:)` and passes the result to
/// `withDependencies { $0.prometheusQuery = port }` before any query is executed.
///
/// ```swift
/// let port = PrometheusQueryAdapter.makePort(httpClient: sharedHTTPClient)
/// // In SwiftUI App body or composition root:
/// withDependencies { $0.prometheusQuery = port } operation: { ... }
/// ```
///
/// `PrometheusHTTPClient` is the concrete conformance; this enum provides a
/// stable public API surface for the module without exposing the implementation
/// type directly.
public enum PrometheusQueryAdapter: Sendable {

    /// Semantic version of this adapter module.
    public static let moduleVersion = "1.0.0"

    /// Creates a `PrometheusQueryPort` backed by the full HTTP client.
    ///
    /// The returned port validates all label values against the ADR-0044 allowlist
    /// (`^[a-zA-Z0-9._-]{1,63}$`) before issuing any HTTP request. Range query
    /// results are downsampled to <= 200 points before being returned.
    ///
    /// - Parameter httpClient: A shared `AsyncHTTPClient` instance. The caller
    ///   owns the lifecycle and must shut it down after use.
    /// - Returns: A `Sendable` port ready for dependency injection.
    public static func makePort(
        httpClient: HTTPClient
    ) -> any PrometheusQueryPort {
        PrometheusHTTPClient(httpClient: httpClient)
    }
}
