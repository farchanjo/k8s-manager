// Ports/EndpointDiscoveryPort.swift — metrics_observability bounded context
// DDD role: Port (primary — outbound to Kubernetes API for discovery)
// ADR ref: ADR-0016 (auto-discovery pipeline: well_known, auto_label, auto_annotation)

import Foundation

// MARK: - EndpointDiscoveryPort

/// Auto-discovers Prometheus endpoint candidates for a given Kubernetes context
/// by querying the Kubernetes API.
///
/// Declared in the domain core; implemented in infrastructure (typically by
/// the same adapter that implements `KubernetesApiPort`). The domain core
/// never imports `SwiftkubeClient` or any networking library.
///
/// Discovery follows the four-tier pipeline defined in ADR-0016:
/// manual_override (highest precedence) → well_known → auto_label →
/// auto_annotation. This port covers tiers 2–4; the manual_override tier
/// is handled directly by the caller before invoking this port.
///
/// All discovered candidates are returned sorted by (namespace ASC, name ASC).
/// The caller selects the first as the active endpoint.
public protocol EndpointDiscoveryPort: Sendable {
    /// Discovers Prometheus endpoint candidates for a Kubernetes context.
    ///
    /// Returns an empty array when no Prometheus Service can be located.
    /// Never throws when discovery simply finds nothing — only raises on
    /// transport or authentication failures.
    ///
    /// - Parameter kubernetesContextId: Stable identifier of the target
    ///   Kubernetes context.
    /// - Returns: Zero or more `PrometheusEndpoint` candidates sorted by
    ///   namespace then Service name.
    /// - Throws: `EndpointDiscoveryError` on API transport failure.
    func discover(
        kubernetesContextId: UUID
    ) async throws -> [PrometheusEndpoint]

    /// Probes a candidate endpoint's health URL and returns a copy with an
    /// updated `status`, `lastProbedAt`, and `version`.
    ///
    /// - Parameter endpoint: The candidate to probe.
    /// - Returns: Updated aggregate with probe results applied.
    /// - Throws: `EndpointDiscoveryError` on transport failure.
    func probe(_ endpoint: PrometheusEndpoint) async throws -> PrometheusEndpoint
}

// MARK: - EndpointDiscoveryError

/// Errors raised by `EndpointDiscoveryPort` implementations.
public enum EndpointDiscoveryError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// The Kubernetes API could not be reached during discovery.
    case kubernetesApiUnavailable(detail: String)

    /// Network or TLS failure while probing the candidate endpoint.
    case probeTransportError(url: String, detail: String)

    /// HTTP 401 / 403 received while probing. Operator attention needed.
    case probeUnauthorized(url: String)
}

// MARK: - UnimplementedEndpointDiscoveryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedEndpointDiscoveryPort: EndpointDiscoveryPort {
    public init() {}

    public func discover(kubernetesContextId: UUID) async throws -> [PrometheusEndpoint] {
        throw EndpointDiscoveryError.unimplemented
    }

    public func probe(_ endpoint: PrometheusEndpoint) async throws -> PrometheusEndpoint {
        throw EndpointDiscoveryError.unimplemented
    }
}
