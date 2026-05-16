// GRDBChatRepository.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl (secondary adapter — outbound to SQLite)
// Implements: ChatRepositoryPort (LocalPersistence)
// ADR refs: ADR-0010, ADR-0027 (redaction policy)

import Foundation
import GRDB
import LocalPersistence
import Logging

// MARK: - GRDBChatRepository

/// SQLite-backed implementation of ``ChatRepositoryPort``.
///
/// All database access is async and routed through the `DatabaseWriter`
/// supplied at init. Use the in-memory queue in tests.
public struct GRDBChatRepository: ChatRepositoryPort {

    private let db: any DatabaseWriter
    private let logger: Logger

    // MARK: Init

    /// - Parameters:
    ///   - db: A `DatabaseQueue` or `DatabasePool`. Owned by the caller.
    ///   - logger: Destination for diagnostic messages.
    public init(db: any DatabaseWriter, logger: Logger = .init(label: "grdb.chat")) {
        self.db = db
        self.logger = logger
    }

    // MARK: ChatRepositoryPort

    public func activeSessions() async throws -> [ChatSession] {
        try await db.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM chat_sessions
                    WHERE archived_at IS NULL
                    ORDER BY updated_at DESC
                    """
            )
            return rows.map(chatSession(from:))
        }
    }

    public func session(id: UUID) async throws -> ChatSession? {
        try await db.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM chat_sessions WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return chatSession(from: row)
        }
    }

    public func createSession(_ session: ChatSession) async throws {
        do {
            try await db.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO chat_sessions
                            (id, created_at, updated_at, title,
                             provider_profile_id, cluster_id, archived_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        session.id.uuidString,
                        Self.iso8601(session.createdAt),
                        Self.iso8601(session.updatedAt),
                        session.title,
                        session.providerProfileId?.uuidString,
                        session.clusterId?.uuidString,
                        session.archivedAt.map(Self.iso8601)
                    ]
                )
            }
        } catch {
            throw ChatRepositoryError.storageError(underlying: error.localizedDescription)
        }
    }

    public func updateSessionTitle(id: UUID, title: String) async throws {
        let count = try await db.write { database -> Int in
            try database.execute(
                sql: "UPDATE chat_sessions SET title = ?, updated_at = ? WHERE id = ?",
                arguments: [title, Self.iso8601(Date()), id.uuidString]
            )
            return database.changesCount
        }
        if count == 0 { throw ChatRepositoryError.sessionNotFound(id: id) }
    }

    public func archiveSession(id: UUID, at date: Date) async throws {
        let count = try await db.write { database -> Int in
            try database.execute(
                sql: "UPDATE chat_sessions SET archived_at = ?, updated_at = ? WHERE id = ?",
                arguments: [Self.iso8601(date), Self.iso8601(date), id.uuidString]
            )
            return database.changesCount
        }
        if count == 0 { throw ChatRepositoryError.sessionNotFound(id: id) }
    }

    public func messages(sessionId: UUID) async throws -> [ChatMessage] {
        try await db.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM chat_messages
                    WHERE session_id = ?
                    ORDER BY created_at ASC
                    """,
                arguments: [sessionId.uuidString]
            )
            return rows.map(chatMessage(from:))
        }
    }

    public func appendMessage(_ message: ChatMessage) async throws {
        do {
            try await db.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO chat_messages
                            (id, session_id, role, content, tool_calls_json, created_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        message.id.uuidString,
                        message.sessionId.uuidString,
                        message.role.rawValue,
                        message.content,
                        message.toolCallsJSON,
                        Self.iso8601(message.createdAt)
                    ]
                )
                try database.execute(
                    sql: "UPDATE chat_sessions SET updated_at = ? WHERE id = ?",
                    arguments: [Self.iso8601(message.createdAt), message.sessionId.uuidString]
                )
            }
        } catch {
            throw ChatRepositoryError.storageError(underlying: error.localizedDescription)
        }
    }

    // MARK: Row mapping

    private func chatSession(from row: Row) -> ChatSession {
        ChatSession(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            createdAt: Self.parseDate(row["created_at"]),
            updatedAt: Self.parseDate(row["updated_at"]),
            title: row["title"],
            providerProfileId: (row["provider_profile_id"] as String?).flatMap(UUID.init),
            clusterId: (row["cluster_id"] as String?).flatMap(UUID.init),
            archivedAt: (row["archived_at"] as String?).map(Self.parseDate)
        )
    }

    private func chatMessage(from row: Row) -> ChatMessage {
        ChatMessage(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            sessionId: UUID(uuidString: row["session_id"]) ?? UUID(),
            role: ChatMessageRole(rawValue: row["role"]) ?? .user,
            content: row["content"],
            toolCallsJSON: row["tool_calls_json"],
            createdAt: Self.parseDate(row["created_at"])
        )
    }

    // MARK: Date helpers

    private static func iso8601Formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func iso8601(_ date: Date) -> String {
        Self.iso8601Formatter().string(from: date)
    }

    private static func parseDate(_ string: String) -> Date {
        Self.iso8601Formatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
    }
}
