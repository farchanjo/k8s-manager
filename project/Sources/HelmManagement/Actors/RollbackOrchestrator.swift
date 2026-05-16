// Actors/RollbackOrchestrator.swift — helm_management bounded context
// DDD role: DomainService (Swift actor — lease + SSA + audit coordination)
// ADR ref: ADR-0015 §Rollback, ADR-0046 §Acquisition protocol

import Dependencies
import Foundation
import SharedKernel

// MARK: - RollbackOrchestrator

/// Coordinates Helm rollback operations: acquires the mutual-exclusion Lease
/// (ADR-0046), reads target-revision manifests, applies them via Server-Side
/// Apply, releases the Lease, and records an audit entry.
///
/// All cluster access is mediated through injected ports. The actor boundary
/// guarantees that internal state mutations (if any future state is added) are
/// race-free under Swift 6 strict concurrency.
///
/// **Rollback flow:**
/// 1. Acquire `coordination.k8s.io/v1/Lease` via `rollbackLease`.
/// 2. Read target-revision `Release` aggregate from `helmReleaseStore`.
/// 3. Split manifest YAML into individual documents and apply each via
///    `serverSideApply` (field manager `com.archanjo.K8sManager`).
/// 4. Release the Lease unconditionally (success or failure).
/// 5. Write an audit entry via `auditLog`.
/// 6. Return the projected `ReleaseHistoryEntry` on success or re-throw on failure.
public actor RollbackOrchestrator {

    // MARK: Init

    /// Creates a `RollbackOrchestrator`. Dependencies resolved lazily via
    /// `@Dependency` on each call so test overrides are respected.
    public init() {}

    // MARK: - rollback(release:toRevision:clusterId:holderIdentity:)

    /// Performs a Helm rollback to a stored revision using Lease mutual exclusion.
    ///
    /// - Parameters:
    ///   - release: The logical release aggregate (any revision) identifying which
    ///     release to roll back (by name + namespace).
    ///   - toRevision: Target Helm revision number (must be ≥ 1).
    ///   - clusterId: Stable identifier of the active cluster context.
    ///   - holderIdentity: Lease holder identity string per ADR-0046.
    ///     Format: `k8smanager-<instanceId>-<operatorEmail>`.
    /// - Returns: A `ReleaseHistoryEntry` for the target revision on success.
    /// - Throws: `RollbackLeaseError.contention` when the Lease is held by
    ///   another instance; `HelmReleaseStoreError` on read/write failure;
    ///   `ServerSideApplyError` on SSA failure; `AuditLogError` on audit failure.
    public func rollback(
        release: Release,
        toRevision: Int,
        clusterId: ClusterId,
        holderIdentity: String
    ) async throws -> ReleaseHistoryEntry {
        @Dependency(\.rollbackLease) var leasePort
        @Dependency(\.helmReleaseStore) var store
        @Dependency(\.serverSideApply) var ssa
        @Dependency(\.auditLog) var audit

        let lease = try await leasePort.acquireLease(
            releaseName: release.name,
            namespace: release.namespace,
            holderIdentity: holderIdentity,
            clusterId: clusterId
        )

        do {
            let targetSecretName = "sh.helm.release.v1.\(release.name).v\(toRevision)"
            let targetRelease = try await store.readRelease(
                secretName: targetSecretName,
                namespace: release.namespace,
                clusterId: clusterId
            )
            let documents = splitYAMLDocuments(targetRelease.manifestYAML)
            for doc in documents where !doc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try await ssa.apply(
                    manifestYAML: doc,
                    namespace: release.namespace,
                    clusterId: clusterId,
                    force: false
                )
            }
            try? await leasePort.releaseLease(lease, clusterId: clusterId)
            try await audit.record(HelmAuditEntry(
                releaseId: release.id,
                revision: toRevision,
                action: .rollbackSucceeded,
                operator: holderIdentity,
                timestamp: ISO8601DateFormatter().string(from: Date())
            ))
            return ReleaseHistoryEntry(
                revision: targetRelease.version,
                deployedAtRFC3339: targetRelease.modifiedAtRFC3339,
                status: targetRelease.status,
                chartVersion: targetRelease.chart.version,
                appVersion: targetRelease.chart.appVersion,
                description: targetRelease.info.description,
                supersededAtRFC3339: nil
            )
        } catch {
            try? await leasePort.releaseLease(lease, clusterId: clusterId)
            try await audit.record(HelmAuditEntry(
                releaseId: release.id,
                revision: toRevision,
                action: .rollbackFailed,
                operator: holderIdentity,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                detail: String(describing: error)
            ))
            throw error
        }
    }

    // MARK: - Private helpers

    /// Splits a multi-document YAML string (separated by `---`) into individual
    /// document strings suitable for one SSA PATCH request each.
    private func splitYAMLDocuments(_ yaml: String) -> [String] {
        yaml.components(separatedBy: "\n---")
    }
}
