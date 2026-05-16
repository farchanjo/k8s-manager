// Ports/NodeDebugPort.swift — terminal_session bounded context
// DDD role: Port (secondary — outbound; ephemeral debug Pod lifecycle)
// ADR ref: ADR-0017 §Decision outcome, §Risks
// Implemented by: KubernetesDebugCreatorAdapter (infrastructure layer)

import Foundation

// MARK: - DebugPodPhase

/// Kubernetes Pod phase values relevant to the debug Pod readiness poll.
public enum DebugPodPhase: String, Hashable, Sendable {
    case pending  = "Pending"
    case running  = "Running"
    case succeeded = "Succeeded"
    case failed   = "Failed"
    case unknown  = "Unknown"
}

// MARK: - NodeDebugPort

/// Creates and deletes the ephemeral debug Pod described by a `NodeDebugDescriptor`.
///
/// Declared in the domain core; implemented by `KubernetesDebugCreatorAdapter`
/// in the infrastructure layer. The domain core never constructs Kubernetes API
/// objects directly.
///
/// ADR-0012 compliance: debug Pod creation is a mutating operation. The domain
/// service (`TerminalSessionActor`) must obtain operator confirmation and write
/// an audit entry before calling `createDebugPod(descriptor:)`.
public protocol NodeDebugPort: Sendable {
    /// Creates the ephemeral debug Pod described by `descriptor`.
    ///
    /// The adapter creates the Pod via the Kubernetes core/v1 Pods API with
    /// `hostNetwork: true`, `hostPID: true`, and `privileged: true` as recorded
    /// in the descriptor, then polls until the Pod reaches `Running` phase or
    /// the operation times out.
    ///
    /// - Parameter descriptor: Immutable descriptor of the Pod to create.
    /// - Returns: The actual Pod name as returned by the API server (may differ
    ///   from `descriptor.ephemeralPodName` on name collision retry).
    /// - Throws: `NodeDebugError` on creation failure or poll timeout.
    func createDebugPod(descriptor: NodeDebugDescriptor) async throws -> String

    /// Deletes the ephemeral debug Pod identified by `podName` in `namespace`.
    ///
    /// Called at session close and at `descriptor.expiresAt` as a safety net.
    /// The adapter issues a graceful delete with a 0-second grace period so
    /// the Pod terminates immediately.
    ///
    /// - Parameters:
    ///   - podName: Name of the Pod to delete.
    ///   - namespace: Kubernetes namespace of the Pod.
    /// - Throws: `NodeDebugError` if the delete call fails for reasons other
    ///   than 404 (already deleted).
    func deleteDebugPod(podName: String, namespace: String) async throws

    /// Polls the debug Pod phase until it reaches `Running` or a timeout fires.
    ///
    /// - Parameters:
    ///   - podName: Name of the Pod to poll.
    ///   - namespace: Kubernetes namespace of the Pod.
    ///   - timeout: Maximum duration to wait. Defaults to 60 s.
    /// - Returns: The final observed `DebugPodPhase`.
    /// - Throws: `NodeDebugError.podTimeout` when `timeout` elapses before
    ///   the Pod reaches `Running`.
    func pollPodPhase(
        podName: String,
        namespace: String,
        timeout: Duration
    ) async throws -> DebugPodPhase
}

// MARK: - NodeDebugError

/// Errors raised by `NodeDebugPort` implementations.
public enum NodeDebugError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// The Kubernetes API rejected the Pod creation request.
    case podCreationFailed(detail: String)
    /// The Pod did not reach `Running` phase within the timeout.
    case podTimeout(podName: String, observed: DebugPodPhase)
    /// The Pod delete call failed.
    case podDeletionFailed(podName: String, detail: String)
    /// A transport-level error occurred during the API call.
    case transportError(detail: String)
}

// MARK: - UnimplementedNodeDebugPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedNodeDebugPort: NodeDebugPort {
    public init() {}

    public func createDebugPod(descriptor: NodeDebugDescriptor) async throws -> String {
        throw NodeDebugError.unimplemented
    }

    public func deleteDebugPod(podName: String, namespace: String) async throws {
        throw NodeDebugError.unimplemented
    }

    public func pollPodPhase(
        podName: String,
        namespace: String,
        timeout: Duration
    ) async throws -> DebugPodPhase {
        throw NodeDebugError.unimplemented
    }
}
