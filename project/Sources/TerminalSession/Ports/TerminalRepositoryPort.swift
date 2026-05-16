// Ports/TerminalRepositoryPort.swift — terminal_session bounded context
// DDD role: Port (secondary — outbound; session metadata persistence)
// CUE source: docs/arch/contexts/terminal_session/schemas/terminal_session.cue
// ADR ref: ADR-0017 §TerminalRepositoryPort, ADR-0010

import Foundation

// MARK: - TerminalRepositoryPort

/// Persists and retrieves `TerminalSession` aggregate metadata.
///
/// Implemented by `GRDBTerminalRepository` in the `GRDBPersistenceAdapter`
/// target. Stdout, stderr, and stdin byte payloads are **never** written to
/// disk (per ADR-0017 invariant "No byte of stdout, stderr, or stdin is
/// persisted"). Only session identity, target reference, lifecycle status,
/// and timestamps are stored.
///
/// On application restart, previously open sessions are surfaced as `.closed`
/// so the operator can decide whether to reopen them. Reconnect is always
/// manual (per ADR-0017 §Reconnect policy).
public protocol TerminalRepositoryPort: Sendable {

    /// Upserts a `TerminalSession` into the persistence store.
    ///
    /// Implementations use INSERT OR REPLACE (or equivalent) so that this
    /// method handles both create and update without the caller distinguishing
    /// between them.
    ///
    /// - Parameter session: The aggregate snapshot to persist.
    /// - Throws: A persistence-layer error on write failure.
    func save(_ session: TerminalSession) async throws

    /// Returns all persisted sessions ordered by `created_at` ascending.
    ///
    /// Called at startup to populate the `OpenTerminalsReadModel`. The
    /// in-memory lifecycle actors for sessions with status `.opening` or
    /// `.open` at crash time will be absent; the UI treats them as `.closed`.
    ///
    /// - Returns: All stored sessions; may be empty.
    /// - Throws: A persistence-layer error on read failure.
    func loadAll() async throws -> [TerminalSession]

    /// Deletes the session record identified by `id`.
    ///
    /// Called when the operator permanently dismisses a closed terminal tab.
    /// Silently succeeds when no record with `id` exists.
    ///
    /// - Parameter id: UUIDv7 of the session to remove.
    /// - Throws: A persistence-layer error on write failure.
    func delete(id: UUID) async throws
}

// MARK: - TerminalRepositoryError

/// Errors raised by `TerminalRepositoryPort` implementations.
public enum TerminalRepositoryError: Error, Sendable {
    /// The underlying storage engine returned an error.
    case storageError(underlying: String)
}

// MARK: - UnimplementedTerminalRepository

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedTerminalRepository: TerminalRepositoryPort {
    /// Creates an unimplemented sentinel instance.
    public init() {}

    public func save(_ session: TerminalSession) async throws {
        throw TerminalRepositoryError.storageError(underlying: "unimplemented")
    }

    public func loadAll() async throws -> [TerminalSession] {
        throw TerminalRepositoryError.storageError(underlying: "unimplemented")
    }

    public func delete(id: UUID) async throws {
        throw TerminalRepositoryError.storageError(underlying: "unimplemented")
    }
}
