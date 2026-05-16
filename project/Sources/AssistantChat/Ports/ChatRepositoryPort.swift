// Ports/ChatRepositoryPort.swift — assistant_chat bounded context
// DDD role: Port (outbound — persistence)
// ADR ref: ADR-0020 (dependency injection strategy)

import Foundation

// MARK: - ChatRepositoryPort

/// Persists and retrieves sessions, messages, and tool-call records for the
/// `assistant_chat` bounded context.
///
/// Declared in the domain core; implemented by the `GRDBPersistenceAdapter` in
/// infrastructure. The domain core never imports GRDB.
public protocol ChatRepositoryPort: Sendable {
    // MARK: Session operations

    /// Persists a new `ChatSession` or replaces an existing one with the same
    /// `id`.
    func upsert(session: ChatSession) async throws

    /// Returns the session with the given `id`, or `nil` when not found.
    func session(id: UUID) async throws -> ChatSession?

    /// Returns all sessions with `status == .active`, ordered by
    /// `updatedAtRFC3339` descending.
    func activeSessions() async throws -> [ChatSession]

    /// Removes the session and all associated messages and tool-call records.
    func delete(sessionId: UUID) async throws

    // MARK: Message operations

    /// Persists a new `ChatMessage` or replaces an existing one with the same
    /// `id`.
    func upsert(message: ChatMessage) async throws

    /// Returns all messages for `sessionId`, ordered by `turn` ascending.
    func messages(sessionId: UUID) async throws -> [ChatMessage]

    // MARK: Tool-call record operations

    /// Persists a new `ToolCallRecord` or replaces an existing one with the
    /// same `callId` and `sessionId`.
    func upsert(toolCallRecord: ToolCallRecord) async throws

    /// Returns all tool-call records whose `parentMessageId` matches.
    func toolCallRecords(parentMessageId: UUID) async throws -> [ToolCallRecord]
}

// MARK: - ChatRepositoryError

/// Errors raised by `ChatRepositoryPort` implementations.
public enum ChatRepositoryError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// A read/write failure at the persistence layer.
    case storageError(detail: String)
    /// The requested resource was not found (soft failure — callers may
    /// prefer the optional-returning variants).
    case notFound(id: String)
}

// MARK: - UnimplementedChatRepositoryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedChatRepositoryPort: ChatRepositoryPort {
    public init() {}

    public func upsert(session: ChatSession) async throws {
        throw ChatRepositoryError.unimplemented
    }

    public func session(id: UUID) async throws -> ChatSession? {
        throw ChatRepositoryError.unimplemented
    }

    public func activeSessions() async throws -> [ChatSession] {
        throw ChatRepositoryError.unimplemented
    }

    public func delete(sessionId: UUID) async throws {
        throw ChatRepositoryError.unimplemented
    }

    public func upsert(message: ChatMessage) async throws {
        throw ChatRepositoryError.unimplemented
    }

    public func messages(sessionId: UUID) async throws -> [ChatMessage] {
        throw ChatRepositoryError.unimplemented
    }

    public func upsert(toolCallRecord: ToolCallRecord) async throws {
        throw ChatRepositoryError.unimplemented
    }

    public func toolCallRecords(parentMessageId: UUID) async throws -> [ToolCallRecord] {
        throw ChatRepositoryError.unimplemented
    }
}
