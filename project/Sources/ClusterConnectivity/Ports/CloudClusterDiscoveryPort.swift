// Ports/CloudClusterDiscoveryPort.swift — cluster_connectivity bounded context
// DDD role: Port (output, hexagonal)
// ADR ref: ADR-0055 (Cloud provider cluster discovery)

import Foundation

// MARK: - CloudClusterDiscoveryError

/// Error surface emitted by `CloudClusterDiscoveryPort` implementations.
///
/// Adapter-specific failure modes map to one of these cases; the operator-
/// facing message is supplied by the adapter and rendered verbatim in the
/// Welcome-tab import sheet.
public enum CloudClusterDiscoveryError: Error, Sendable, Hashable {
    /// Credential chain failed to produce a usable token for the provider.
    case missingCredentials(provider: CloudProvider, detail: String)

    /// Authentication succeeded but the principal lacks the IAM/RBAC
    /// permissions required for discovery.
    case permissionDenied(provider: CloudProvider, detail: String)

    /// The cloud control-plane endpoint was unreachable. Operators should
    /// retry; the adapter does not implement automatic retry on this case.
    case endpointUnreachable(provider: CloudProvider, detail: String)

    /// The adapter is registered but the feature is not yet implemented.
    /// Used by the stub adapters before EKS/AKS/GKE HTTP plumbing lands.
    case notImplemented(provider: CloudProvider)

    /// An underlying transport or serialisation error occurred.
    case transport(provider: CloudProvider, detail: String)
}

// MARK: - DiscoveryResult

/// Aggregated result of a discovery call.
///
/// Carries the descriptors enumerated, plus any non-fatal advisory
/// warnings the adapter emitted during scope resolution or cluster
/// description.
public struct DiscoveryResult: Sendable, Hashable {
    public let clusters: [ClusterDescriptor]
    public let warnings: [DiscoveryWarning]

    public init(clusters: [ClusterDescriptor], warnings: [DiscoveryWarning] = []) {
        self.clusters = clusters
        self.warnings = warnings
    }

    /// Empty result with no clusters and no warnings — useful for default
    /// values in tests and for the "no clusters reachable" surface.
    public static let empty = DiscoveryResult(clusters: [], warnings: [])
}

// MARK: - CloudClusterDiscoveryPort

/// Output port (hexagonal) for enumerating Kubernetes clusters hosted by a
/// cloud provider and for materialising a kubeconfig entry per cluster.
///
/// Implementations live in dedicated adapter targets (`AWSExecCredentialAdapter`,
/// `AzureExecCredentialAdapter`, `GCPExecCredentialAdapter`) and reuse the
/// credential chain established by their ADR-0018 siblings. The domain core
/// sees only this protocol and the supporting value types.
///
/// Adapters are expected to be safe to call concurrently from multiple tabs
/// (Welcome tab discovery, future cluster-strip "Add Cluster" flow, etc.).
public protocol CloudClusterDiscoveryPort: Sendable {

    /// Lists every cluster reachable with the supplied credentials, optionally
    /// scoped by region/subscription/project hints.
    ///
    /// Discovery adapters must not throw on partial failure — instead, return
    /// the clusters that succeeded and emit `DiscoveryWarning` entries for
    /// the failed scopes. Throwing is reserved for failures that prevent any
    /// discovery (missing credentials, hard permission deny, endpoint down).
    func listClusters(
        provider: CloudProvider,
        credentials: CloudCredentialContext,
        scopeHints: CloudScopeHints
    ) async throws -> DiscoveryResult

    /// Materialises a kubeconfig entry (cluster + context + user with exec
    /// block) for the given descriptor.
    ///
    /// The exec block structure matches the cloud CLI conventions documented
    /// in ADR-0055 § "Kubeconfig materialisation rules" so K8sManager output
    /// merge-aligns with existing operator kubeconfigs.
    func materialiseKubeconfig(
        clusterDescriptor: ClusterDescriptor
    ) async throws -> KubeconfigEntry
}
