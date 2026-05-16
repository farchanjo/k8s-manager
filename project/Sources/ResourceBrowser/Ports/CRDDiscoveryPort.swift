// Ports/CRDDiscoveryPort.swift — resource_browser bounded context
// DDD role: Port (outbound — CRD discovery from Kubernetes API)
// ADR ref: ADR-0052 (custom resource discovery and rendering)

import Dependencies
import SharedKernel

// MARK: - CRDDiscoveryError

/// Errors raised by `CRDDiscoveryPort` implementations.
public enum CRDDiscoveryError: Error, Sendable {
    /// The service account lacks permission to list CRDs.
    case unauthorized
    /// Network or TLS failure before a response was received.
    case transportError(detail: String)
    /// Port not registered in this process.
    case unimplemented
}

// MARK: - CRDDiscoveryPort

/// Discovers CustomResourceDefinitions from a Kubernetes cluster.
///
/// Declared in the domain core; implemented by
/// `SwiftkubeCRDDiscoveryAdapter` in infrastructure. The domain core never
/// imports `AsyncHTTPClient` or `SwiftkubeClient`.
public protocol CRDDiscoveryPort: Sendable {

    /// Performs a one-shot list of all CRDs visible in the cluster.
    ///
    /// - Parameter clusterId: The cluster to query.
    /// - Returns: An immutable `CRDCatalog` snapshot.
    /// - Throws: `CRDDiscoveryError` on network or permission failures.
    func discoverCRDs(clusterId: ClusterId) async throws -> CRDCatalog

    /// Opens a long-lived watch stream that emits a new `CRDCatalog` each
    /// time the CRD set changes (add / update / delete).
    ///
    /// Callers should cancel iteration on view disappearance. The stream
    /// terminates when the adapter is deallocated or when a fatal error occurs.
    ///
    /// - Parameter clusterId: The cluster to watch.
    /// - Returns: An `AsyncThrowingStream` of catalog snapshots.
    func watchCRDChanges(clusterId: ClusterId) -> AsyncThrowingStream<CRDCatalog, Error>
}

// MARK: - UnimplementedCRDDiscoveryPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedCRDDiscoveryPort: CRDDiscoveryPort {
    /// Memberwise initialiser.
    public init() {}

    public func discoverCRDs(clusterId: ClusterId) async throws -> CRDCatalog {
        throw CRDDiscoveryError.unimplemented
    }

    public func watchCRDChanges(clusterId: ClusterId) -> AsyncThrowingStream<CRDCatalog, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CRDDiscoveryError.unimplemented)
        }
    }
}

// MARK: - DependencyKey

/// `DependencyKey` for `CRDDiscoveryPort`.
///
/// Both `liveValue` and `testValue` are the `Unimplemented` sentinel so the
/// build is clean with no adapter linked.
public enum CRDDiscoveryPortKey: DependencyKey {
    public static let liveValue: any CRDDiscoveryPort = UnimplementedCRDDiscoveryPort()
    public static let testValue: any CRDDiscoveryPort = UnimplementedCRDDiscoveryPort()
}

public extension DependencyValues {
    /// The port that discovers and watches CustomResourceDefinitions.
    var crdDiscovery: any CRDDiscoveryPort {
        get { self[CRDDiscoveryPortKey.self] }
        set { self[CRDDiscoveryPortKey.self] = newValue }
    }
}
