// Ports/AuditLogPort.swift — helm_management bounded context
// DDD role: Port (outbound — Helm-specific audit log separate from resource_browser's MutationAuditPort)
// ADR ref: ADR-0015 §Rollback (audit entry before API call), ADR-0046 §Contention

import Foundation
import SharedKernel

// MARK: - HelmAuditAction

/// The Helm lifecycle action being audited.
public enum HelmAuditAction: String, Hashable, Sendable, Codable, CaseIterable {
    /// A rollback operation was initiated and succeeded.
    case rollbackSucceeded = "rollback_succeeded"

    /// A rollback operation was initiated but failed.
    case rollbackFailed = "rollback_failed"

    /// A rollback was blocked due to concurrent lease contention.
    case rollbackContention = "rollback_contention"

    /// A rollback was aborted because the Server-Side Apply step failed.
    case rollbackAborted = "rollback_aborted"
}

// MARK: - HelmAuditEntry

/// A single Helm-specific audit record emitted by `RollbackOrchestrator`.
///
/// Separate from `resource_browser`'s `MutationAuditPort` — Helm rollback
/// has additional fields (revision, contention holder) that do not map
/// cleanly onto the generic mutation audit schema.
///
/// The backing store (`local_persistence`) persists these via the
/// `cluster_mutation_audit` table; column mapping must respect the existing
/// `mutation_audit_entry.cue` schema from `resource_browser`.
public struct HelmAuditEntry: Hashable, Sendable, Codable {
    /// Stable identifier of the `Release` aggregate being rolled back.
    /// Corresponds to `Release.id`.
    public let releaseId: UUID

    /// Helm revision number that was the rollback target.
    public let revision: Int

    /// The Helm lifecycle action being audited.
    public let action: HelmAuditAction

    /// Identity of the operator who initiated the action.
    /// Format: `k8smanager-<instanceId>-<operatorEmail>` per ADR-0046.
    public let `operator`: String

    /// RFC3339 timestamp at which this audit entry was written.
    public let timestamp: String

    /// Optional detail string for failures, contention, or abort reasons.
    public let detail: String?

    public init(
        releaseId: UUID,
        revision: Int,
        action: HelmAuditAction,
        operator operatorIdentity: String,
        timestamp: String,
        detail: String? = nil
    ) {
        self.releaseId = releaseId
        self.revision = revision
        self.action = action
        self.operator = operatorIdentity
        self.timestamp = timestamp
        self.detail = detail
    }
}

// MARK: - AuditLogPort

/// Records Helm-specific audit entries for rollback operations.
///
/// Declared in `helm_management`; implemented by an adapter in the
/// `local_persistence` infrastructure layer. The domain core never imports
/// GRDB or any persistence framework directly.
///
/// Per ADR-0015 §Rollback: an audit entry with `action=rollbackSucceeded`
/// or `action=rollbackFailed` must be written before any cluster API call
/// is dispatched.
public protocol AuditLogPort: Sendable {
    /// Persists a Helm audit entry.
    ///
    /// - Parameter entry: The audit record to write.
    /// - Throws: `AuditLogError` on persistence failure.
    func record(_ entry: HelmAuditEntry) async throws
}

// MARK: - AuditLogError

/// Errors raised by `AuditLogPort` implementations.
public enum AuditLogError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// The underlying persistence layer returned an error.
    case persistenceFailed(detail: String)
}

// MARK: - UnimplementedAuditLogPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedAuditLogPort: AuditLogPort {
    public init() {}

    public func record(_ entry: HelmAuditEntry) async throws {
        throw AuditLogError.unimplemented
    }
}
