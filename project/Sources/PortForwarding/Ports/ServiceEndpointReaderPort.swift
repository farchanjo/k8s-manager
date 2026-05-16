// Ports/ServiceEndpointReaderPort.swift — port_forwarding bounded context
// DDD role: Port (secondary — outbound, Service → Pod resolution)
// ADR ref: ADR-0014 (session-open resolution of ServiceTarget to PodTarget)
// Narrative ref: docs/arch/contexts/port_forwarding/domain/narrative.md §ServiceEndpointReaderPort

import Foundation

// MARK: - ServiceEndpointReaderPort

/// Secondary port that resolves a Kubernetes Service to its backing ``PodTarget`` list.
///
/// Called by `PortForwardManagerActor` during session open when the ``ForwardTarget``
/// is a ``ServiceTarget``. The actor selects one ready Pod from the returned list
/// (typically the first) and establishes the WebSocket tunnel to that Pod.
///
/// Implemented by an infrastructure adapter that queries the Kubernetes EndpointSlice
/// API via `KubernetesApiPort` from `cluster_connectivity`.
///
/// Invariant: the returned array is never empty on success. If no ready Pod backs the
/// Service, the implementation throws ``ServiceEndpointReaderError/noReadyPodsFound``.
public protocol ServiceEndpointReaderPort: Sendable {
    /// Resolves the backing ``PodTarget`` list for a Kubernetes Service.
    ///
    /// Queries the EndpointSlice for `service` in `namespace` and returns only Pods
    /// whose readiness condition is `Ready == true`.
    ///
    /// - Parameters:
    ///   - service: Name of the Kubernetes Service to resolve.
    ///   - namespace: Kubernetes namespace that contains the Service.
    /// - Returns: One or more ready ``PodTarget`` values backed by the Service.
    /// - Throws: ``ServiceEndpointReaderError`` on API failure or when no ready Pod exists.
    func resolveEndpoint(for service: String, namespace: String) async throws -> [PodTarget]
}

// MARK: - ServiceEndpointReaderError

/// Errors raised by ``ServiceEndpointReaderPort`` implementations.
public enum ServiceEndpointReaderError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// The Kubernetes API returned a non-success response.
    case apiError(statusCode: Int, detail: String)
    /// The Service exists but has no Pods in the `Ready` state.
    case noReadyPodsFound(service: String, namespace: String)
    /// The Service was not found in the given namespace.
    case serviceNotFound(service: String, namespace: String)
}

// MARK: - UnimplementedServiceEndpointReaderPort

/// Crash-fast sentinel used before an infrastructure adapter registers a real implementation.
public struct UnimplementedServiceEndpointReaderPort: ServiceEndpointReaderPort {
    public init() {}

    public func resolveEndpoint(for service: String, namespace: String) async throws -> [PodTarget] {
        throw ServiceEndpointReaderError.unimplemented
    }
}
