// PrometheusQueryAdapter.swift — infrastructure adapter placeholder
// Implements: MetricsQueryPort from MetricsObservability
// Library: swift-server/async-http-client (Tier A per ADR-0019)
// Status: skeleton; port implementations pending domain ports definition.
import AsyncHTTPClient
import MetricsObservability
import Foundation

/// Namespace marker for the PrometheusQueryAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum PrometheusQueryAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
