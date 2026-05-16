// Ports/PrometheusEndpointRepositoryPort.swift — metrics_observability bounded context
// DDD role: Port (secondary — outbound to persistence layer)
// ADR ref: ADR-0016 (endpoint lifecycle), ADR-0020 (dependency injection strategy)

import Foundation

// MARK: - PrometheusEndpointRepositoryPort

/// Persists and loads `PrometheusEndpoint` aggregates for all configured or
/// discovered Prometheus instances.
///
/// Declared in the domain core; implemented by the persistence adapter
/// (e.g., `GRDBPersistenceAdapter`). The domain core never imports GRDB.
///
/// Persistence is append-and-replace: `save(_:)` replaces the entire
/// stored set for the contained `kubernetesContextId` values. Callers
/// are responsible for deduplication before calling `save`.
public protocol PrometheusEndpointRepositoryPort: Sendable {
    /// Persists the given array of endpoints, replacing any previously stored
    /// endpoints for the same `kubernetesContextId`.
    ///
    /// An empty array clears all stored endpoints for the represented contexts.
    ///
    /// - Parameter endpoints: The endpoints to store.
    /// - Throws: `PrometheusEndpointRepositoryError.persistenceFailure` on write error.
    func save(_ endpoints: [PrometheusEndpoint]) async throws

    /// Returns all stored `PrometheusEndpoint` values across all contexts,
    /// sorted by `kubernetesContextId` then `url`.
    ///
    /// Returns an empty array when no endpoints have been stored yet.
    ///
    /// - Throws: `PrometheusEndpointRepositoryError.persistenceFailure` on read error.
    func load() async throws -> [PrometheusEndpoint]
}

// MARK: - PrometheusEndpointRepositoryError

/// Errors raised by `PrometheusEndpointRepositoryPort` implementations.
public enum PrometheusEndpointRepositoryError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// An underlying persistence operation failed.
    case persistenceFailure(detail: String)
}

// MARK: - UnimplementedPrometheusEndpointRepositoryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedPrometheusEndpointRepositoryPort: PrometheusEndpointRepositoryPort {
    public init() {}

    public func save(_ endpoints: [PrometheusEndpoint]) async throws {
        throw PrometheusEndpointRepositoryError.unimplemented
    }

    public func load() async throws -> [PrometheusEndpoint] {
        throw PrometheusEndpointRepositoryError.unimplemented
    }
}
