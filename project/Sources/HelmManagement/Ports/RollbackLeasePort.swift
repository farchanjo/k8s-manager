// Ports/RollbackLeasePort.swift — helm_management bounded context
// DDD role: Port (outbound — manages coordination.k8s.io/v1/Lease for rollback mutex)
// ADR ref: ADR-0046 (Helm rollback Lease-based mutual exclusion)

import Foundation
import SharedKernel

// MARK: - RollbackLeasePort

/// Manages `coordination.k8s.io/v1/Lease` objects that provide mutual exclusion
/// for concurrent rollback operations per ADR-0046.
///
/// Each Helm release gets a dedicated Lease named
/// `k8smanager-helm-rollback-<release-name>` in the release's namespace.
/// The acquisition protocol prevents two operators or two app instances from
/// rolling back the same release simultaneously.
///
/// Acquisition protocol (ADR-0046 §Acquisition):
/// 1. GET the Lease. If absent, POST with our `holderIdentity`.
/// 2. If found and stale (`renewTime + leaseDurationSeconds < now`),
///    PUT with our `holderIdentity` using `resourceVersion` optimistic concurrency.
/// 3. If found, not stale, and holder differs from ours, abort with
///    `RollbackLeaseError.contention`.
///
/// Renewal: callers invoke `renewLease` every 20 seconds while rollback is
/// in progress. If renewal fails (stolen lease), abort the rollback.
///
/// Release: callers invoke `releaseLease` on completion (success or failure).
public protocol RollbackLeasePort: Sendable {
    /// Attempts to acquire the rollback Lease for the given release.
    ///
    /// - Parameters:
    ///   - releaseName: Helm release name. Used to construct the Lease name.
    ///   - namespace: Kubernetes namespace of the Helm release.
    ///   - holderIdentity: Our identity string. Format per ADR-0046:
    ///     `k8smanager-<instanceId>-<operatorEmail>`.
    ///   - clusterId: Stable identifier of the active cluster context.
    /// - Returns: The acquired `RollbackLease` value object on success.
    /// - Throws: `RollbackLeaseError.contention` when another live holder
    ///   owns the lease, or `RollbackLeaseError` variants on API failures.
    func acquireLease(
        releaseName: String,
        namespace: String,
        holderIdentity: String,
        clusterId: ClusterId
    ) async throws -> RollbackLease

    /// Renews the `renewTime` on an already-acquired Lease.
    ///
    /// Called every `RollbackLease.renewIntervalSeconds` (20 s) while rollback
    /// is in progress. If renewal fails because the Lease was overwritten by a
    /// competing instance, returns `RollbackLeaseError.stolen`.
    ///
    /// - Parameters:
    ///   - lease: The currently-held `RollbackLease`.
    ///   - clusterId: Stable identifier of the active cluster context.
    /// - Returns: An updated `RollbackLease` with the new `renewTime`.
    /// - Throws: `RollbackLeaseError.stolen` or other API errors.
    func renewLease(
        _ lease: RollbackLease,
        clusterId: ClusterId
    ) async throws -> RollbackLease

    /// Deletes the rollback Lease on rollback completion (success or failure).
    ///
    /// If deletion fails, the lease auto-expires after `leaseDurationSeconds`.
    ///
    /// - Parameters:
    ///   - lease: The currently-held `RollbackLease` to release.
    ///   - clusterId: Stable identifier of the active cluster context.
    /// - Throws: `RollbackLeaseError` on API failure. Non-fatal; callers should
    ///   log and continue.
    func releaseLease(
        _ lease: RollbackLease,
        clusterId: ClusterId
    ) async throws
}

// MARK: - RollbackLeaseError

/// Errors raised by `RollbackLeasePort` implementations.
public enum RollbackLeaseError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// Another live holder owns the rollback Lease for this release.
    /// Contains the conflicting `holderIdentity` for operator UX messaging.
    case contention(holderIdentity: String)

    /// The Lease was overwritten by a competing instance during renewal.
    /// The rollback must be aborted; no new Secret should be written.
    case stolen

    /// `resourceVersion`-based optimistic concurrency failed (HTTP 409).
    /// Caller should retry acquisition from the beginning.
    case conflict

    /// Network or TLS failure.
    case transportError(detail: String)

    /// Unexpected HTTP status from the API server.
    case unexpectedStatus(code: Int, detail: String)
}

// MARK: - UnimplementedRollbackLeasePort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedRollbackLeasePort: RollbackLeasePort {
    public init() {}

    public func acquireLease(
        releaseName: String,
        namespace: String,
        holderIdentity: String,
        clusterId: ClusterId
    ) async throws -> RollbackLease {
        throw RollbackLeaseError.unimplemented
    }

    public func renewLease(
        _ lease: RollbackLease,
        clusterId: ClusterId
    ) async throws -> RollbackLease {
        throw RollbackLeaseError.unimplemented
    }

    public func releaseLease(
        _ lease: RollbackLease,
        clusterId: ClusterId
    ) async throws {
        throw RollbackLeaseError.unimplemented
    }
}
