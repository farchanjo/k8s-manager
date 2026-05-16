// GRDBHelmAuditLogAdapter.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl (secondary adapter — outbound to SQLite)
// Implements: AuditLogPort (HelmManagement)
// ADR ref: ADR-0015 §Rollback (audit entry before API call),
//          ADR-0046 §Contention (RollbackContention audit entry)

import Foundation
import GRDB
import HelmManagement
import Logging

// MARK: - GRDBHelmAuditLogAdapter

/// SQLite-backed implementation of ``AuditLogPort`` for Helm rollback events.
///
/// Writes append-only rows to the `helm_audit_log` table (added in migration
/// v4). Each entry records the release identity, revision, action, operator
/// identity, and an optional detail string.
///
/// This adapter does NOT implement HMAC chain integrity — the Helm audit log
/// is an operational record of rollback intent, separate from the cryptographic
/// mutation audit chain (`cluster_mutation_audit`). If chain integrity for Helm
/// events is required in a future ADR, a new migration and HMAC adapter can be
/// added without changing this type.
public struct GRDBHelmAuditLogAdapter: AuditLogPort {

    // MARK: - Properties

    private let db: any DatabaseWriter
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates the adapter backed by the shared `DatabaseWriter`.
    ///
    /// - Parameters:
    ///   - db: Shared `DatabaseQueue` / `DatabasePool`. Must already have
    ///     migration `v4_helm_audit_log` applied.
    ///   - logger: Diagnostics destination.
    public init(
        db: any DatabaseWriter,
        logger: Logger = .init(label: "grdb.helm-audit")
    ) {
        self.db = db
        self.logger = logger
    }

    // MARK: - AuditLogPort

    /// Persists a Helm audit entry to the `helm_audit_log` table.
    ///
    /// - Parameter entry: The audit record to write.
    /// - Throws: `AuditLogError.persistenceFailed` on GRDB write failure.
    public func record(_ entry: HelmAuditEntry) async throws {
        do {
            try await db.write { database in
                try insertRow(entry: entry, in: database)
            }
            logger.debug(
                "helm_audit_log: recorded \(entry.action.rawValue) for release \(entry.releaseId)"
            )
        } catch {
            throw AuditLogError.persistenceFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Private — GRDB helpers

    private func insertRow(entry: HelmAuditEntry, in database: Database) throws {
        try database.execute(
            sql: """
                INSERT INTO helm_audit_log (
                    id, release_id, revision, action,
                    operator_identity, timestamp, detail
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                UUID().uuidString,
                entry.releaseId.uuidString,
                entry.revision,
                entry.action.rawValue,
                entry.operator,
                entry.timestamp,
                entry.detail
            ]
        )
    }
}
