// Ports/MutationAuditPort.swift — resource_browser bounded context
// DDD role: Port (outbound — append-only audit log persistence)
// ADR ref: ADR-0012 (audit log, tamper-evidence chain)

import Foundation
import SharedKernel

// MARK: - MutationAuditPort

/// Writes immutable audit entries to the `cluster_mutation_audit` SQLite table.
///
/// The table is owned by `local_persistence`; the column mapping must match the
/// CUE schema in `contexts/resource_browser/schemas/mutation_audit_entry.cue`.
///
/// Rows are append-only. The SQLite-level `BEFORE UPDATE OR DELETE` trigger
/// enforces immutability at the database layer (ADR-0012).
///
/// Declared in the domain core; implemented by `GRDBPersistenceAdapter`.
public protocol MutationAuditPort: Sendable {
    /// Persists a new audit entry before the API call is dispatched.
    ///
    /// Implementations MUST write the row before returning so that a crash
    /// after this call cannot produce an unaudited mutation.
    ///
    /// - Parameter entry: The fully constructed `MutationAuditEntry`.
    /// - Throws: `AuditError` if the row cannot be written.
    func record(_ entry: MutationAuditEntry) async throws

    /// Updates the `outcome`, `completedAt`, and `kubernetesStatusCode` fields
    /// of an existing audit entry after the API call completes.
    ///
    /// This is the ONLY permitted update path. The SQLite trigger blocks all
    /// other `UPDATE` statements.
    ///
    /// - Parameters:
    ///   - id: The `UUID` of the audit entry to update.
    ///   - outcome: Final outcome of the mutation.
    ///   - completedAt: RFC3339 timestamp when the outcome was determined.
    ///   - kubernetesStatusCode: HTTP status code from the API server. `nil`
    ///     when no API call was made.
    /// - Throws: `AuditError` if the row cannot be updated or does not exist.
    func complete(
        id: UUID,
        outcome: MutationOutcome,
        completedAt: String,
        kubernetesStatusCode: Int?
    ) async throws

    /// Returns a reverse-chronological page of audit entries for a cluster.
    ///
    /// - Parameters:
    ///   - contextId: Cluster context filter.
    ///   - limit: Maximum number of rows to return.
    ///   - offset: Pagination offset.
    /// - Returns: Array of `MutationAuditEntry` values, newest first.
    /// - Throws: `AuditError` on database failures.
    func entries(
        contextId: UUID,
        limit: Int,
        offset: Int
    ) async throws -> [MutationAuditEntry]
}

// MARK: - AuditError

/// Errors raised by `MutationAuditPort` implementations.
public enum AuditError: Error, Sendable {
    /// Port not registered in this process.
    case unimplemented

    /// A database-level error occurred (wraps the underlying message).
    case databaseError(detail: String)

    /// The requested entry was not found.
    case entryNotFound(id: UUID)

    /// A duplicate `requestId` was detected; submission rejected before dispatch.
    case duplicateEntry(id: UUID)
}

// MARK: - UnimplementedMutationAuditPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedMutationAuditPort: MutationAuditPort {
    public init() {}

    public func record(_ entry: MutationAuditEntry) async throws {
        throw AuditError.unimplemented
    }

    public func complete(
        id: UUID,
        outcome: MutationOutcome,
        completedAt: String,
        kubernetesStatusCode: Int?
    ) async throws {
        throw AuditError.unimplemented
    }

    public func entries(
        contextId: UUID,
        limit: Int,
        offset: Int
    ) async throws -> [MutationAuditEntry] {
        throw AuditError.unimplemented
    }
}
