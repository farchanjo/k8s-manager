// Ports/KubernetesResourceListPort.swift — resource_browser bounded context
// DDD role: Port (outbound — Kubernetes read operations)
// ADR refs: ADR-0013 (kind catalogue), ADR-0012 (list verbs)

import SharedKernel

// MARK: - KubernetesResourceListPort

/// Fetches and enumerates Kubernetes resources from the API server.
///
/// Declared in the domain core; implemented by `SwiftkubeClientAdapter` in
/// infrastructure. The domain core never imports `AsyncHTTPClient` or
/// `SwiftkubeClient`.
///
/// Covers the `list` and `get` verbs from the ADR-0013 kind catalogue.
public protocol KubernetesResourceListPort: Sendable {
    /// Fetches a paginated list of resources for the given GVK.
    ///
    /// - Parameters:
    ///   - gvk: The Kubernetes API type to list.
    ///   - namespace: Namespace filter. `nil` lists across all namespaces.
    ///   - clusterId: The active cluster identifier (kubeconfig cluster name).
    /// - Returns: An array of `ResourceListItem` projections.
    /// - Throws: `ResourceListError` on network or API failures.
    func list(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> [ResourceListItem]

    /// Fetches the full detail for a single resource.
    ///
    /// - Parameters:
    ///   - gvk: The Kubernetes API type.
    ///   - name: Resource name.
    ///   - namespace: Namespace. `nil` for cluster-scoped resources.
    ///   - clusterId: The active cluster identifier (kubeconfig cluster name).
    /// - Returns: A fully populated `ResourceDetail`.
    /// - Throws: `ResourceListError` on network or API failures.
    func get(
        gvk: GroupVersionKind,
        name: String,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> ResourceDetail
}

// MARK: - ResourceListError

/// Errors raised by `KubernetesResourceListPort` implementations.
public enum ResourceListError: Error, Sendable {
    /// Port not registered in this process.
    case unimplemented

    /// Network or TLS failure before a response was received.
    case transportError(detail: String)

    /// The API server returned an unexpected HTTP status code.
    case unexpectedStatus(code: Int, detail: String)

    /// The requested GVK is not registered in the kind catalogue.
    case unknownGVK(GroupVersionKind)

    /// The resource was not found (HTTP 404).
    case notFound(name: String, gvk: GroupVersionKind)
}

// MARK: - UnimplementedKubernetesResourceListPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedKubernetesResourceListPort: KubernetesResourceListPort {
    public init() {}

    public func list(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> [ResourceListItem] {
        throw ResourceListError.unimplemented
    }

    public func get(
        gvk: GroupVersionKind,
        name: String,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> ResourceDetail {
        throw ResourceListError.unimplemented
    }
}
