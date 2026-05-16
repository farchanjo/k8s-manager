// Ports/PortForwardRepositoryPort.swift — port_forwarding bounded context
// DDD role: Port (secondary — outbound, persistence)
// ADR ref: ADR-0014 (session persistence to SQLite via local_persistence)
// Narrative ref: docs/arch/contexts/port_forwarding/domain/narrative.md §PortForwardRepositoryPort

import Foundation

// MARK: - PortForwardRepositoryPort

/// Secondary port that persists ``PortForwardSession`` aggregates to SQLite via the
/// `local_persistence` bounded context.
///
/// Used by `PortForwardManagerActor` to write session state at lifecycle transitions
/// so that the UI can restore the session list after application relaunch.
///
/// Invariant: on application relaunch, all previously stored sessions are surfaced
/// with status `closed`; no re-activation attempt is ever made. Byte payloads from
/// the tunnel are never persisted (ADR-0014 §Security and operational constraints).
public protocol PortForwardRepositoryPort: Sendable {
    /// Persists or updates a ``PortForwardSession`` aggregate.
    ///
    /// An upsert semantic is used: if a session with `session.id` already exists,
    /// it is replaced in full. If it does not exist, a new record is inserted.
    ///
    /// - Parameter session: The aggregate to persist.
    /// - Throws: ``PortForwardRepositoryError/saveFailed`` on storage failure.
    func save(_ session: PortForwardSession) async throws

    /// Returns all stored ``PortForwardSession`` aggregates, ordered by
    /// `createdAtRFC3339` descending.
    ///
    /// On application relaunch, the returned sessions will reflect their persisted
    /// status (typically `closed` or `error`). The caller must not attempt to
    /// reactivate any returned session; create a new aggregate instead.
    ///
    /// - Returns: All persisted sessions, or an empty array if none exist.
    /// - Throws: ``PortForwardRepositoryError/loadFailed`` on storage failure.
    func loadAll() async throws -> [PortForwardSession]

    /// Removes the ``PortForwardSession`` with the given `id` from persistent storage.
    ///
    /// Calling `delete(id:)` for an `id` that does not exist is a no-op.
    ///
    /// - Parameter id: UUIDv7 of the session to delete.
    /// - Throws: ``PortForwardRepositoryError/deleteFailed`` on storage failure.
    func delete(id: UUID) async throws
}

// MARK: - PortForwardRepositoryError

/// Errors raised by ``PortForwardRepositoryPort`` implementations.
public enum PortForwardRepositoryError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// A `save` operation failed at the storage layer.
    case saveFailed(detail: String)
    /// A `loadAll` operation failed at the storage layer.
    case loadFailed(detail: String)
    /// A `delete` operation failed at the storage layer.
    case deleteFailed(id: UUID, detail: String)
}

// MARK: - UnimplementedPortForwardRepositoryPort

/// Crash-fast sentinel used before an infrastructure adapter registers a real implementation.
public struct UnimplementedPortForwardRepositoryPort: PortForwardRepositoryPort {
    public init() {}

    public func save(_ session: PortForwardSession) async throws {
        throw PortForwardRepositoryError.unimplemented
    }

    public func loadAll() async throws -> [PortForwardSession] {
        throw PortForwardRepositoryError.unimplemented
    }

    public func delete(id: UUID) async throws {
        throw PortForwardRepositoryError.unimplemented
    }
}
