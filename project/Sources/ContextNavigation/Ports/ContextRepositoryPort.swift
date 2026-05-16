// Ports/ContextRepositoryPort.swift — context_navigation bounded context
// DDD role: Port (primary — inbound/outbound persistence)
// Narrative ref: domain/narrative.md §Tactical roles (ContextRepositoryPort)

import Foundation
import SharedKernel

// MARK: - ContextRepositoryPort

/// Persists and retrieves pins, recents, and the last-known active context.
///
/// Declared in the domain core; implemented by a `UserDefaults`-backed adapter
/// at the infrastructure layer. The domain core never imports `UserDefaults`
/// or any storage library.
public protocol ContextRepositoryPort: Sendable {
    /// Loads the persisted recents window. Returns an empty window with the
    /// default cap when no data has been stored yet.
    func loadRecentWindow() async throws -> RecentContextWindow

    /// Persists the updated recents window.
    func saveRecentWindow(_ window: RecentContextWindow) async throws

    /// Loads all persisted pinned contexts, ordered by `displayOrder`.
    func loadPinnedContexts() async throws -> [PinnedContext]

    /// Persists a new pin. Idempotent if the context is already pinned.
    func pin(_ context: PinnedContext) async throws

    /// Removes the pin for the given context. No-op when not pinned.
    func unpin(contextId: ContextId) async throws

    /// Loads the active context snapshot persisted at the last launch.
    /// Returns `nil` on first launch or after a clean reset.
    func loadLastActiveContext() async throws -> ActiveContext?

    /// Persists the current active context for restoration at next launch.
    func saveLastActiveContext(_ context: ActiveContext) async throws
}

// MARK: - ContextRepositoryError

/// Errors raised by `ContextRepositoryPort` implementations.
public enum ContextRepositoryError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// The persisted data could not be decoded (e.g., schema migration gap).
    case decodeError(detail: String)

    /// The storage layer returned an unexpected error.
    case storageError(underlying: String)
}

// MARK: - UnimplementedContextRepositoryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedContextRepositoryPort: ContextRepositoryPort {
    public init() {}

    public func loadRecentWindow() async throws -> RecentContextWindow {
        throw ContextRepositoryError.unimplemented
    }

    public func saveRecentWindow(_ window: RecentContextWindow) async throws {
        throw ContextRepositoryError.unimplemented
    }

    public func loadPinnedContexts() async throws -> [PinnedContext] {
        throw ContextRepositoryError.unimplemented
    }

    public func pin(_ context: PinnedContext) async throws {
        throw ContextRepositoryError.unimplemented
    }

    public func unpin(contextId: ContextId) async throws {
        throw ContextRepositoryError.unimplemented
    }

    public func loadLastActiveContext() async throws -> ActiveContext? {
        throw ContextRepositoryError.unimplemented
    }

    public func saveLastActiveContext(_ context: ActiveContext) async throws {
        throw ContextRepositoryError.unimplemented
    }
}
