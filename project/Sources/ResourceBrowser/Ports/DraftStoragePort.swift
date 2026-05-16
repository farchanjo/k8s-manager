// Ports/DraftStoragePort.swift — resource_browser bounded context
// DDD role: Port (outbound — draft entity persistence)
// ADR ref: ADR-0030 (integrated editor MD / YAML / JSON)

import Foundation
import SharedKernel

// MARK: - DraftStoragePort

/// Persists and retrieves `Draft` entities in the `editor_drafts` SQLite table.
///
/// Used by `DraftAutoSaver` (every 5 seconds while `isDirty == true`) and by
/// `EditorOrchestratorService` at session open time (draft restoration).
///
/// Declared in the domain core; implemented by `GRDBPersistenceAdapter`.
public protocol DraftStoragePort: Sendable {
    /// Persists a draft snapshot. If a row with the same `id` already exists,
    /// it is replaced in full (upsert semantics).
    ///
    /// When `draft.resourceRef.kind` is `"Secret"` the content field MUST have
    /// had `data`/`stringData` values replaced with `"[REDACTED]"` before this
    /// call. `DraftAutoSaver` is responsible for that redaction.
    ///
    /// - Parameter draft: The `Draft` entity to persist.
    /// - Throws: `DraftStorageError` on database failures.
    func save(_ draft: Draft) async throws

    /// Returns the most-recent draft for the given editor session, if any.
    ///
    /// - Parameter sessionId: The `EditorSession.id` to look up.
    /// - Returns: The newest `Draft` for that session, or `nil`.
    /// - Throws: `DraftStorageError` on database failures.
    func latestDraft(forSession sessionId: UUID) async throws -> Draft?

    /// Returns all drafts associated with a Kubernetes resource, ordered by
    /// `savedAt` descending.
    ///
    /// Used to offer draft resumption when the operator re-opens a resource
    /// they were previously editing.
    ///
    /// - Parameter resourceRef: The `ResourceRef` to look up.
    /// - Returns: An array of `Draft` values, newest first.
    /// - Throws: `DraftStorageError` on database failures.
    func drafts(forResource resourceRef: ResourceRef) async throws -> [Draft]

    /// Deletes a draft by its primary key.
    ///
    /// Called after the operator applies the manifest or explicitly discards
    /// the draft. Silently succeeds if the draft does not exist.
    ///
    /// - Parameter id: The `Draft.id` to delete.
    /// - Throws: `DraftStorageError` on database failures.
    func delete(id: UUID) async throws

    /// Deletes all drafts older than `olderThan` that have no corresponding
    /// active session. Used by the garbage-collection sweep at application start.
    ///
    /// - Parameter olderThan: RFC3339 timestamp; drafts with `savedAt` before
    ///   this value are eligible for deletion.
    /// - Returns: Number of rows deleted.
    /// - Throws: `DraftStorageError` on database failures.
    func pruneStale(olderThan: String) async throws -> Int
}

// MARK: - DraftStorageError

/// Errors raised by `DraftStoragePort` implementations.
public enum DraftStorageError: Error, Sendable {
    /// Port not registered in this process.
    case unimplemented

    /// A database-level error occurred (wraps the underlying message).
    case databaseError(detail: String)
}

// MARK: - UnimplementedDraftStoragePort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedDraftStoragePort: DraftStoragePort {
    public init() {}

    public func save(_ draft: Draft) async throws {
        throw DraftStorageError.unimplemented
    }

    public func latestDraft(forSession sessionId: UUID) async throws -> Draft? {
        throw DraftStorageError.unimplemented
    }

    public func drafts(forResource resourceRef: ResourceRef) async throws -> [Draft] {
        throw DraftStorageError.unimplemented
    }

    public func delete(id: UUID) async throws {
        throw DraftStorageError.unimplemented
    }

    public func pruneStale(olderThan: String) async throws -> Int {
        throw DraftStorageError.unimplemented
    }
}
