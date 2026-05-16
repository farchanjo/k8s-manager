// Ports/ResourceMetadataPort.swift — analytics_dashboard bounded context
// DDD role: Port (outbound — consumes cluster_connectivity and resource_browser)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Ports
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Used by TopologyGraph, ConditionsList, StackedBar (pod phases), and Count
// (node ready count) widgets.

import Foundation

// MARK: - KubernetesCondition

/// A Kubernetes `.status.conditions[]` entry for a resource.
public struct KubernetesCondition: Sendable, Codable, Hashable {
    /// Condition type (e.g., `"Ready"`, `"Available"`, `"Progressing"`).
    public let type: String
    /// Condition status: `"True"`, `"False"`, or `"Unknown"`.
    public let status: String
    /// Machine-readable reason for the current status.
    public let reason: String?
    /// Human-readable message.
    public let message: String?
    /// RFC 3339 timestamp when this condition was last transitioned.
    public let lastTransitionTime: String?

    /// Designated initialiser.
    public init(
        type: String,
        status: String,
        reason: String? = nil,
        message: String? = nil,
        lastTransitionTime: String? = nil
    ) {
        self.type = type
        self.status = status
        self.reason = reason
        self.message = message
        self.lastTransitionTime = lastTransitionTime
    }
}

// MARK: - TopologyEdge

/// A directed edge in a Kubernetes resource topology graph.
public struct TopologyEdge: Sendable, Codable, Hashable {
    /// The source resource reference.
    public let from: ResourceRef
    /// The target resource reference.
    public let to: ResourceRef
    /// Edge label (e.g., `"ownerRef"`, `"selector"`, `"helmRelease"`).
    public let label: String

    /// Designated initialiser.
    public init(from: ResourceRef, to: ResourceRef, label: String) {
        self.from = from
        self.to = to
        self.label = label
    }
}

// MARK: - TopologyGraph

/// Result returned by `ResourceMetadataPort.topologyGraph(...)`.
public struct TopologyGraph: Sendable, Codable, Hashable {
    /// All nodes in the graph, starting from the root.
    public let nodes: [ResourceRef]
    /// Directed edges between nodes.
    public let edges: [TopologyEdge]

    /// Designated initialiser.
    public init(nodes: [ResourceRef], edges: [TopologyEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

// MARK: - ResourceMetadataPort

/// Reads Kubernetes object state, conditions, owner references, and YAML snapshots.
///
/// Consumes `cluster_connectivity` (object state, conditions, owner references,
/// endpoint lists) and `resource_browser` read models (resource counts, YAML
/// snapshots).
///
/// Used by:
/// - `TopologyGraphWidget` — graph nodes and edges.
/// - `ConditionsListWidget` — `.status.conditions[]` array.
/// - `StackedBarWidget` — pod phase distribution.
/// - `CountWidget` — node ready count, deployment availability.
public protocol ResourceMetadataPort: Sendable {
    /// Returns the `.status.conditions[]` array for the given resource.
    ///
    /// - Parameters:
    ///   - resourceRef: API coordinates of the target resource.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: The current conditions, may be empty.
    /// - Throws: `ResourceMetadataError` on connectivity failure.
    func conditions(
        for resourceRef: ResourceRef,
        inContext kubernetesContextId: String
    ) async throws -> [KubernetesCondition]

    /// Returns the topology graph rooted at the given resource reference.
    ///
    /// - Parameters:
    ///   - rootRef: Starting resource for graph traversal.
    ///   - depthLimit: Maximum edge hops from the root.
    ///   - includeServices: When `true`, Service → Endpoints → Pod edges are included.
    ///   - includeOwnerRefs: When `true`, Pod → ReplicaSet → Deployment edges are included.
    ///   - includeHelmReleases: When `true`, HelmRelease → managed-resource edges are included.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: The topology graph for the root resource.
    /// - Throws: `ResourceMetadataError` on connectivity failure.
    func topologyGraph(
        rootRef: ResourceRef,
        depthLimit: Int,
        includeServices: Bool,
        includeOwnerRefs: Bool,
        includeHelmReleases: Bool,
        inContext kubernetesContextId: String
    ) async throws -> TopologyGraph

    /// Returns the count of resources matching the given label selector.
    ///
    /// - Parameters:
    ///   - kind: Kubernetes resource kind (e.g., `"Pod"`, `"Node"`).
    ///   - namespace: Namespace to scope the query. `nil` for cluster-scoped resources.
    ///   - labelSelector: Kubernetes label selector syntax. `nil` for no filter.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: The count of matching resources.
    func resourceCount(
        kind: String,
        namespace: String?,
        labelSelector: String?,
        inContext kubernetesContextId: String
    ) async throws -> Int
}

// MARK: - ResourceMetadataError

/// Errors raised by `ResourceMetadataPort` implementations.
public enum ResourceMetadataError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// The referenced resource does not exist.
    case resourceNotFound(ResourceRef)
    /// Connectivity failure when fetching metadata.
    case transportError(detail: String)
    /// Response could not be decoded.
    case decodeError(detail: String)
}

// MARK: - UnimplementedResourceMetadataPort

/// Crash-fast sentinel used as `liveValue` / `testValue` until an adapter registers.
public struct UnimplementedResourceMetadataPort: ResourceMetadataPort {
    public init() {}

    public func conditions(for _: ResourceRef, inContext _: String) async throws -> [KubernetesCondition] {
        throw ResourceMetadataError.unimplemented
    }

    public func topologyGraph(
        rootRef _: ResourceRef,
        depthLimit _: Int,
        includeServices _: Bool,
        includeOwnerRefs _: Bool,
        includeHelmReleases _: Bool,
        inContext _: String
    ) async throws -> TopologyGraph {
        throw ResourceMetadataError.unimplemented
    }

    public func resourceCount(
        kind _: String,
        namespace _: String?,
        labelSelector _: String?,
        inContext _: String
    ) async throws -> Int {
        throw ResourceMetadataError.unimplemented
    }
}
