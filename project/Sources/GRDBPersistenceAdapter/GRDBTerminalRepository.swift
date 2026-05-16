// GRDBTerminalRepository.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl (secondary adapter — outbound to SQLite)
// Implements: TerminalRepositoryPort (TerminalSession)
// ADR refs: ADR-0010 (WAL, PRAGMAs, migrations), ADR-0017 (terminal sessions)

import Foundation
import GRDB
import TerminalSession
import Logging

// MARK: - GRDBTerminalRepository

/// SQLite-backed implementation of ``TerminalRepositoryPort``.
///
/// All database access is async and routed through the `DatabaseWriter`
/// supplied at init. Use the in-memory queue returned by
/// `SchemaMigrator._runV2(_:)` in tests.
///
/// Stdout, stderr, and stdin byte payloads are **never** stored here.
/// Only session identity, target reference, lifecycle status, and timestamps
/// are persisted (per ADR-0017 invariant).
public struct GRDBTerminalRepository: TerminalRepositoryPort {

    private let db: any DatabaseWriter
    private let logger: Logger

    // MARK: Init

    /// - Parameters:
    ///   - db: A `DatabaseQueue` or `DatabasePool`. Owned by the caller.
    ///   - logger: Destination for diagnostic messages.
    public init(db: any DatabaseWriter, logger: Logger = .init(label: "grdb.terminal")) {
        self.db = db
        self.logger = logger
    }

    // MARK: TerminalRepositoryPort

    public func save(_ session: TerminalSession) async throws {
        do {
            try await db.write { database in
                try database.execute(
                    sql: """
                        INSERT OR REPLACE INTO terminal_session
                            (id, cluster_id, namespace, pod, container,
                             kind, status, created_at, last_active_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: makeArguments(for: session)
                )
            }
        } catch {
            logger.error("GRDBTerminalRepository.save failed: \(error)")
            throw TerminalRepositoryError.storageError(underlying: error.localizedDescription)
        }
    }

    public func loadAll() async throws -> [TerminalSession] {
        do {
            return try await db.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: "SELECT * FROM terminal_session ORDER BY created_at ASC"
                )
                return rows.compactMap(terminalSession(from:))
            }
        } catch {
            throw TerminalRepositoryError.storageError(underlying: error.localizedDescription)
        }
    }

    public func delete(id: UUID) async throws {
        do {
            try await db.write { database in
                try database.execute(
                    sql: "DELETE FROM terminal_session WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        } catch {
            throw TerminalRepositoryError.storageError(underlying: error.localizedDescription)
        }
    }

    // MARK: Row mapping

    private func makeArguments(for session: TerminalSession) -> StatementArguments {
        let (namespace, pod, container) = extractPodCoordinates(from: session.targetRef)
        return StatementArguments([
            session.id.uuidString,
            session.kubernetesContextId.uuidString,
            namespace,
            pod,
            container,
            session.kind.rawValue,
            session.status.rawValue,
            session.createdAt,
            session.lastActivityAt
        ])
    }

    private func extractPodCoordinates(from target: SessionTarget) -> (String, String, String?) {
        switch target {
        case .pod(let t):
            return (t.namespace, t.podName, t.containerName)
        case .node(let t):
            return ("default", "node-debugger-\(t.nodeName)", t.debugContainerName)
        }
    }

    private func terminalSession(from row: Row) -> TerminalSession? {
        guard
            let idString = row["id"] as String?,
            let id = UUID(uuidString: idString),
            let clusterIdString = row["cluster_id"] as String?,
            let clusterId = UUID(uuidString: clusterIdString),
            let kindRaw = row["kind"] as String?,
            let kind = SessionKind(rawValue: kindRaw),
            let statusRaw = row["status"] as String?,
            let status = SessionStatus(rawValue: statusRaw),
            let createdAt = row["created_at"] as String?,
            let lastActiveAt = row["last_active_at"] as String?
        else { return nil }

        let namespace = (row["namespace"] as String?) ?? "default"
        let pod = (row["pod"] as String?) ?? ""
        let container = row["container"] as String?

        let target: SessionTarget
        if kind == .podExec {
            target = .pod(PodTarget(namespace: namespace, podName: pod, containerName: container))
        } else {
            let nodeName = pod.hasPrefix("node-debugger-") ? String(pod.dropFirst("node-debugger-".count)) : pod
            target = .node(NodeTarget(nodeName: nodeName, debugContainerName: container ?? "debugger"))
        }

        return TerminalSession(
            id: id,
            kind: kind,
            kubernetesContextId: clusterId,
            targetRef: target,
            command: ["/bin/sh"],
            tty: true,
            stdin: true,
            createdAt: createdAt,
            lastActivityAt: lastActiveAt,
            status: status == .opening || status == .open ? .closed : status
        )
    }
}
