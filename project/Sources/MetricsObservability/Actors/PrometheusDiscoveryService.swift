// Actors/PrometheusDiscoveryService.swift — metrics_observability bounded context
// DDD role: DomainService (Swift actor — auto-discovery pipeline)
// ADR ref: ADR-0016 (auto-discovery: auto_label + auto_annotation tiers)

import ClusterConnectivity
import Dependencies
import Foundation

// MARK: - PrometheusDiscoveryService

/// Discovers Prometheus endpoints for a given Kubernetes cluster by querying
/// the Kubernetes API for Services carrying the expected annotation or label.
///
/// Discovery order per ADR-0016 (tiers 3 and 4):
/// - `auto_annotation`: Services with annotation `prometheus.io/scrape=true`.
/// - `auto_label`: Services with label `app.kubernetes.io/name=prometheus`.
///
/// Results are sorted by (namespace ASC, url ASC) for stable precedence.
/// The caller is responsible for applying the `manual_override` and
/// `well_known` tiers before invoking this actor.
public actor PrometheusDiscoveryService {

    // MARK: Private dependencies

    @Dependency(\.endpointDiscovery) private var discoveryPort

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Discovers Prometheus endpoint candidates for a given Kubernetes cluster.
    ///
    /// Delegates to `EndpointDiscoveryPort`, which queries the Kubernetes API
    /// for Services annotated with `prometheus.io/scrape=true` or labelled
    /// with `app.kubernetes.io/name=prometheus`.
    ///
    /// Returns an empty array when no suitable Service is found. Never throws
    /// on an empty result — only raises on transport or authentication failures.
    ///
    /// - Parameter clusterId: The `UUID` identifying the target Kubernetes
    ///   context as stored in `PrometheusEndpoint.kubernetesContextId`.
    /// - Returns: Zero or more `PrometheusEndpoint` candidates, sorted by
    ///   discovery source precedence then URL.
    /// - Throws: `EndpointDiscoveryError` on API transport failure.
    public func discover(in clusterId: UUID) async throws -> [PrometheusEndpoint] {
        let candidates = try await discoveryPort.discover(kubernetesContextId: clusterId)
        return candidates.sorted { lhs, rhs in
            if lhs.discoverySource.rawValue != rhs.discoverySource.rawValue {
                return lhs.discoverySource.rawValue < rhs.discoverySource.rawValue
            }
            return lhs.url < rhs.url
        }
    }
}
