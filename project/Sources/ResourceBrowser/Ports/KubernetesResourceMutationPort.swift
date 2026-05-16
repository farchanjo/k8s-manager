// Ports/KubernetesResourceMutationPort.swift — resource_browser bounded context
// DDD role: Port (outbound — Kubernetes write operations via SSA)
// ADR refs: ADR-0012 (mutation policy, SSA field manager), ADR-0013 (kind catalogue)

import Foundation
import SharedKernel

// MARK: - KubernetesResourceMutationPort

/// Dispatches approved mutation commands to the Kubernetes API server.
///
/// Server-side apply (SSA) is the only apply strategy. The application never
/// uses client-side apply. Every request carries the fixed field manager
/// `com.archanjo.K8sManager` (ADR-0012).
///
/// Declared in the domain core; implemented by `SwiftkubeClientAdapter`.
public protocol KubernetesResourceMutationPort: Sendable {
    /// Issues a server-side apply PATCH for the given command.
    ///
    /// Sets `Content-Type: application/apply-patch+yaml` and, when
    /// `command.forceConflicts == true`, appends `?force=true`.
    ///
    /// - Parameters:
    ///   - command: The approved `ApplyYAML` command.
    ///   - contextId: The active cluster context identifier.
    /// - Returns: HTTP status code returned by the API server.
    /// - Throws: `MutationError` on network, API, or conflict failures.
    func applyYAML(
        command: ApplyYAML,
        contextId: UUID
    ) async throws -> Int

    /// Issues a PATCH on the `/scale` subresource.
    ///
    /// - Parameters:
    ///   - command: The approved `ScaleReplicas` command.
    ///   - contextId: The active cluster context identifier.
    /// - Returns: HTTP status code returned by the API server.
    /// - Throws: `MutationError` on network or API failures.
    func scaleReplicas(
        command: ScaleReplicas,
        contextId: UUID
    ) async throws -> Int

    /// Issues a strategic merge PATCH injecting `kubectl.kubernetes.io/restartedAt`.
    ///
    /// - Parameters:
    ///   - command: The approved `RolloutRestart` command.
    ///   - contextId: The active cluster context identifier.
    /// - Returns: HTTP status code returned by the API server.
    /// - Throws: `MutationError` on network or API failures.
    func rolloutRestart(
        command: RolloutRestart,
        contextId: UUID
    ) async throws -> Int

    /// Issues a DELETE request for the specified resource.
    ///
    /// Requires `doubleConfirmed == true` to have been asserted by the UI layer
    /// before the command is dispatched.
    ///
    /// - Parameters:
    ///   - command: The approved `DeleteResource` command.
    ///   - contextId: The active cluster context identifier.
    /// - Returns: HTTP status code returned by the API server.
    /// - Throws: `MutationError` on network or API failures.
    func deleteResource(
        command: DeleteResource,
        contextId: UUID
    ) async throws -> Int

    /// Issues a strategic merge PATCH on `metadata.labels`.
    ///
    /// - Parameters:
    ///   - command: The approved `LabelPatch` command.
    ///   - contextId: The active cluster context identifier.
    /// - Returns: HTTP status code returned by the API server.
    /// - Throws: `MutationError` on network or API failures.
    func labelPatch(
        command: LabelPatch,
        contextId: UUID
    ) async throws -> Int

    /// Issues a strategic merge PATCH on `metadata.annotations`.
    ///
    /// - Parameters:
    ///   - command: The approved `AnnotationPatch` command.
    ///   - contextId: The active cluster context identifier.
    /// - Returns: HTTP status code returned by the API server.
    /// - Throws: `MutationError` on network or API failures.
    func annotationPatch(
        command: AnnotationPatch,
        contextId: UUID
    ) async throws -> Int
}

// MARK: - MutationError

/// Errors raised by `KubernetesResourceMutationPort` implementations.
public enum MutationError: Error, Sendable {
    /// Port not registered in this process.
    case unimplemented

    /// Network or TLS failure before a response was received.
    case transportError(detail: String)

    /// The API server returned an unexpected HTTP status code.
    case unexpectedStatus(code: Int, detail: String)

    /// SSA field ownership conflict (HTTP 409). Force-ownership is required.
    case fieldConflict(conflicts: [FieldConflict])

    /// The `resourceVersion` in the request does not match the current etcd version.
    case resourceVersionConflict(detail: String)

    /// The mutation guard policy denied the command.
    case deniedByPolicy(reasons: [String])
}

// MARK: - UnimplementedKubernetesResourceMutationPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedKubernetesResourceMutationPort: KubernetesResourceMutationPort {
    public init() {}

    public func applyYAML(command: ApplyYAML, contextId: UUID) async throws -> Int {
        throw MutationError.unimplemented
    }

    public func scaleReplicas(command: ScaleReplicas, contextId: UUID) async throws -> Int {
        throw MutationError.unimplemented
    }

    public func rolloutRestart(command: RolloutRestart, contextId: UUID) async throws -> Int {
        throw MutationError.unimplemented
    }

    public func deleteResource(command: DeleteResource, contextId: UUID) async throws -> Int {
        throw MutationError.unimplemented
    }

    public func labelPatch(command: LabelPatch, contextId: UUID) async throws -> Int {
        throw MutationError.unimplemented
    }

    public func annotationPatch(command: AnnotationPatch, contextId: UUID) async throws -> Int {
        throw MutationError.unimplemented
    }
}
