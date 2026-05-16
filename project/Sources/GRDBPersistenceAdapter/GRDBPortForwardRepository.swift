// GRDBPortForwardRepository.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl (secondary adapter — outbound to SQLite)
// Implements: PortForwardRepositoryPort (PortForwarding)
// ADR refs: ADR-0010 (WAL, PRAGMAs, migrations), ADR-0007 (PortForwarding persistence)

import Foundation
import GRDB
import Logging
import PortForwarding

// MARK: - GRDBPortForwardRepository

/// SQLite-backed implementation of ``PortForwardRepositoryPort``.
///
/// ``PortForwardSession`` is stored as a JSON blob in the `payload_json` column
/// so all nested value types (`ForwardTarget`, `PortMapping`, etc.) are preserved
/// without additional schema columns.
///
/// On relaunch, sessions are returned as-is. The caller is responsible for
/// interpreting terminal states (`closed`, `error`) and must not reactivate them.
///
/// Wire payloads are never stored here (ADR-0007 / ADR-0014 §Security).
public struct GRDBPortForwardRepository: PortForwardRepositoryPort {

    private let db: any DatabaseWriter
    private let logger: Logger
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Init

    /// - Parameters:
    ///   - db: A `DatabaseQueue` or `DatabasePool`. Owned by the caller.
    ///   - logger: Destination for diagnostic messages.
    public init(db: any DatabaseWriter, logger: Logger = .init(label: "grdb.port_forward")) {
        self.db = db
        self.logger = logger
    }

    // MARK: PortForwardRepositoryPort

    public func save(_ session: PortForwardSession) async throws {
        do {
            let json = try encoder.encode(session)
            guard let payload = String(data: json, encoding: .utf8) else {
                throw PortForwardRepositoryError.saveFailed(detail: "JSON encoding produced nil string")
            }
            try await db.write { database in
                try database.execute(
                    sql: """
                        INSERT OR REPLACE INTO port_forward_session
                            (id, kubernetes_context_id, status, created_at, payload_json)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        session.id.uuidString,
                        session.kubernetesContextId.uuidString,
                        session.status.rawValue,
                        session.createdAtRFC3339,
                        payload,
                    ]
                )
            }
        } catch let err as PortForwardRepositoryError {
            throw err
        } catch {
            logger.error("GRDBPortForwardRepository.save failed: \(error)")
            throw PortForwardRepositoryError.saveFailed(detail: error.localizedDescription)
        }
    }

    public func loadAll() async throws -> [PortForwardSession] {
        do {
            return try await db.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                        SELECT payload_json FROM port_forward_session
                        ORDER BY created_at DESC
                        """
                )
                return rows.compactMap { row -> PortForwardSession? in
                    guard let json = row["payload_json"] as String?,
                          let data = json.data(using: .utf8) else { return nil }
                    return try? self.decoder.decode(PortForwardSession.self, from: data)
                }
            }
        } catch {
            logger.error("GRDBPortForwardRepository.loadAll failed: \(error)")
            throw PortForwardRepositoryError.loadFailed(detail: error.localizedDescription)
        }
    }

    public func delete(id: UUID) async throws {
        do {
            try await db.write { database in
                try database.execute(
                    sql: "DELETE FROM port_forward_session WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        } catch {
            logger.error("GRDBPortForwardRepository.delete failed id=\(id): \(error)")
            throw PortForwardRepositoryError.deleteFailed(
                id: id,
                detail: error.localizedDescription
            )
        }
    }
}
