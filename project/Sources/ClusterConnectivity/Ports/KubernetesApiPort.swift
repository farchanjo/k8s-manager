// Ports/KubernetesApiPort.swift — cluster_connectivity bounded context
// DDD role: Port (primary — outbound to Kubernetes API server)
// ADR ref: ADR-0002 (SwiftkubeClient adapter)
// Narrative ref: domain/narrative.md §Tactical roles

import Foundation
import SharedKernel

// MARK: - KubernetesApiPort

/// Probes a Kubernetes cluster's health endpoint and retrieves server metadata.
///
/// Declared in the domain core; implemented by `SwiftkubeClientAdapter` in
/// infrastructure. The domain core never imports `AsyncHTTPClient` or
/// `SwiftkubeClient`.
public protocol KubernetesApiPort: Sendable {
    /// Probes the health endpoint (`/readyz` or `/healthz`) of the given
    /// cluster and returns an immutable `HealthStatus`.
    ///
    /// - Parameter clusterId: The shared-kernel identifier of the cluster to
    ///   probe.
    /// - Returns: An immutable `HealthStatus` value object.
    /// - Throws: Any transport-level error encountered during the probe.
    func probeHealth(clusterId: ClusterId) async throws -> HealthStatus

    /// Fetches the server version string from the cluster's `/version`
    /// endpoint.
    ///
    /// - Parameter clusterId: The shared-kernel identifier of the cluster.
    /// - Returns: A human-readable version string (e.g.
    ///   `"v1.29.3+k3s1"`).
    /// - Throws: Any transport-level error encountered during the request.
    func serverVersion(clusterId: ClusterId) async throws -> String
}

// MARK: - KubernetesApiError

/// Errors raised by `KubernetesApiPort` implementations.
public enum KubernetesApiError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// Network or TLS failure before a response was received.
    case transportError(detail: String)

    /// The API server returned an unexpected HTTP status code.
    case unexpectedStatus(code: Int, detail: String)
}

// MARK: - UnimplementedKubernetesApiPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedKubernetesApiPort: KubernetesApiPort {
    public init() {}

    public func probeHealth(clusterId: ClusterId) async throws -> HealthStatus {
        throw KubernetesApiError.unimplemented
    }

    public func serverVersion(clusterId: ClusterId) async throws -> String {
        throw KubernetesApiError.unimplemented
    }
}
