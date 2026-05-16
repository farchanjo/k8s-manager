// Ports/ChatRepositoryPort.swift — local_persistence bounded context
// DDD role: Port (secondary — outbound to persistence infrastructure)
// Consumed by: assistant_chat bounded context
// Narrative ref: domain/narrative.md §Tactical roles
// DBML ref: storage.dbml §chat_sessions, §chat_messages

import Foundation
import SharedKernel

// MARK: - ChatSession

/// Lightweight read-model for a chat session returned by the repository.
///
/// The GRDB row-level record is the adapter's concern; the domain core only
/// sees this projection.
public struct ChatSession: Hashable, Sendable, Codable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let title: String?
    /// UUIDv7 of the LLM provider profile. `nil` when the profile was deleted.
    public let providerProfileId: UUID?
    /// UUIDv7 of the pinned cluster. `nil` for sessions not tied to a cluster.
    public let clusterId: UUID?
    public let archivedAt: Date?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        title: String? = nil,
        providerProfileId: UUID? = nil,
        clusterId: UUID? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.providerProfileId = providerProfileId
        self.clusterId = clusterId
        self.archivedAt = archivedAt
    }
}

// MARK: - ChatMessageRole

/// Message role discriminant matching the `role` column constraint.
public enum ChatMessageRole: String, Hashable, Sendable, Codable {
    case system    = "system"
    case user      = "user"
    case assistant = "assistant"
    case tool      = "tool"
}

// MARK: - ChatMessage

/// Lightweight read-model for a single chat message.
public struct ChatMessage: Hashable, Sendable, Codable {
    public let id: UUID
    public let sessionId: UUID
    public let role: ChatMessageRole
    /// Full message content. For tool results this is the rendered output.
    public let content: String
    /// Serialised tool-call array for assistant turns. `nil` for other roles.
    public let toolCallsJSON: String?
    public let createdAt: Date

    public init(
        id: UUID,
        sessionId: UUID,
        role: ChatMessageRole,
        content: String,
        toolCallsJSON: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.toolCallsJSON = toolCallsJSON
        self.createdAt = createdAt
    }
}

// MARK: - ChatRepositoryError

/// Errors raised by `ChatRepositoryPort` implementations.
public enum ChatRepositoryError: Error, Sendable {
    /// No session exists for the given identifier.
    case sessionNotFound(id: UUID)
    /// A write was rejected by the redaction policy (ADR-0027).
    case redactionPolicyViolation(field: String)
    /// The underlying persistence layer returned an error.
    case storageError(underlying: String)
    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - ChatRepositoryPort

/// Port for reading and writing chat sessions and messages.
///
/// Declared in the domain core; implemented by the `GRDBPersistenceAdapter`
/// target. The domain core never imports GRDB.
public protocol ChatRepositoryPort: Sendable {
    /// Returns all non-archived sessions ordered by `updatedAt` descending.
    func activeSessions() async throws -> [ChatSession]

    /// Returns the session identified by `id`, or `nil` when absent.
    func session(id: UUID) async throws -> ChatSession?

    /// Inserts a new session record.
    ///
    /// - Throws: `ChatRepositoryError.storageError` on persistence failure.
    func createSession(_ session: ChatSession) async throws

    /// Updates the `title` field of an existing session.
    ///
    /// - Throws: `ChatRepositoryError.sessionNotFound` when absent.
    func updateSessionTitle(id: UUID, title: String) async throws

    /// Marks a session as archived by setting `archivedAt` to `now`.
    ///
    /// - Throws: `ChatRepositoryError.sessionNotFound` when absent.
    func archiveSession(id: UUID, at date: Date) async throws

    /// Returns all messages for `sessionId` ordered by `createdAt` ascending.
    func messages(sessionId: UUID) async throws -> [ChatMessage]

    /// Appends a new message to an existing session.
    ///
    /// Also bumps `chat_sessions.updatedAt` to `message.createdAt`.
    ///
    /// - Throws: `ChatRepositoryError.redactionPolicyViolation` when the
    ///   content contains a credential-shaped value (ADR-0027).
    func appendMessage(_ message: ChatMessage) async throws
}

// MARK: - UnimplementedChatRepositoryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedChatRepositoryPort: ChatRepositoryPort {
    public init() {}

    public func activeSessions() async throws -> [ChatSession] {
        throw ChatRepositoryError.unimplemented
    }

    public func session(id: UUID) async throws -> ChatSession? {
        throw ChatRepositoryError.unimplemented
    }

    public func createSession(_ session: ChatSession) async throws {
        throw ChatRepositoryError.unimplemented
    }

    public func updateSessionTitle(id: UUID, title: String) async throws {
        throw ChatRepositoryError.unimplemented
    }

    public func archiveSession(id: UUID, at date: Date) async throws {
        throw ChatRepositoryError.unimplemented
    }

    public func messages(sessionId: UUID) async throws -> [ChatMessage] {
        throw ChatRepositoryError.unimplemented
    }

    public func appendMessage(_ message: ChatMessage) async throws {
        throw ChatRepositoryError.unimplemented
    }
}
