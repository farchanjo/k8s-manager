// Ports/ServerSideApplyPort.swift — helm_management bounded context
// DDD role: Port (cross-context — consumes the SSA pipeline from cluster_connectivity)
// ADR ref: ADR-0015 §Rollback, ADR-0012 (mutating operations policy)
//
// This port is declared in helm_management but its live implementation is
// provided by the SwiftkubeClientAdapter which is also shared with
// cluster_connectivity and resource_browser. The field manager is fixed at
// `com.archanjo.K8sManager` per ADR-0015 §FieldManager.

import Foundation
import SharedKernel

// MARK: - ServerSideApplyPort

/// Issues Server-Side Apply PATCH requests for Helm rollback manifest application.
///
/// Consumed by `RollbackOrchestrator` to apply the stored manifest YAML from a
/// target revision to the cluster. SSA delegates field ownership and merge
/// semantics to the Kubernetes API server, replacing the need for a Swift port
/// of `strategicpatch`.
///
/// Field manager is fixed to `com.archanjo.K8sManager` per ADR-0015.
/// Force-apply is `false` by default; set `force: true` only when the domain
/// service has determined that a field conflict must be resolved.
public protocol ServerSideApplyPort: Sendable {
    /// Applies a single YAML document to the cluster using Server-Side Apply.
    ///
    /// - Parameters:
    ///   - manifestYAML: A single Kubernetes resource YAML document (not a
    ///     multi-document stream). The resource's `apiVersion`, `kind`, and
    ///     `metadata.name` must be present.
    ///   - namespace: Kubernetes namespace for namespaced resources. Ignored
    ///     for cluster-scoped resources.
    ///   - clusterId: Stable identifier of the active cluster context.
    ///   - force: When `true`, the apply forcefully takes ownership of
    ///     conflicted fields. Default is `false`.
    /// - Returns: An `ApplyOutcome` describing what changed.
    /// - Throws: `ServerSideApplyError` on transport or API failure.
    func apply(
        manifestYAML: String,
        namespace: String,
        clusterId: ClusterId,
        force: Bool
    ) async throws -> ApplyOutcome
}

// MARK: - ApplyOutcome

/// Result of a successful Server-Side Apply PATCH.
public struct ApplyOutcome: Hashable, Sendable {
    /// The `apiVersion` of the applied resource.
    public let apiVersion: String

    /// The Kubernetes resource `kind`.
    public let kind: String

    /// The resource `metadata.name`.
    public let name: String

    /// HTTP status code returned by the API server.
    /// `200` = updated, `201` = created.
    public let httpStatus: Int

    public init(apiVersion: String, kind: String, name: String, httpStatus: Int) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.name = name
        self.httpStatus = httpStatus
    }
}

// MARK: - ServerSideApplyError

/// Errors raised by `ServerSideApplyPort` implementations.
public enum ServerSideApplyError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// The API server returned a `404 Not Found` for the resource's API group.
    /// Indicates a missing CRD; maps to `RollbackAborted(detail: .crdMissing)`.
    case crdMissing(apiVersion: String, kind: String)

    /// The API server returned `409 Conflict` with field ownership information.
    case fieldConflict(detail: String)

    /// Network or TLS failure.
    case transportError(detail: String)

    /// Unexpected HTTP status from the API server.
    case unexpectedStatus(code: Int, detail: String)
}

// MARK: - UnimplementedServerSideApplyPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedServerSideApplyPort: ServerSideApplyPort {
    public init() {}

    public func apply(
        manifestYAML: String,
        namespace: String,
        clusterId: ClusterId,
        force: Bool
    ) async throws -> ApplyOutcome {
        throw ServerSideApplyError.unimplemented
    }
}
