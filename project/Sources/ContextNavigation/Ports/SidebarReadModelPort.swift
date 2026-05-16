// Ports/SidebarReadModelPort.swift — context_navigation bounded context
// DDD role: Port (outbound — read model queries for app_shell)
// Narrative ref: domain/narrative.md §Read models exposed to other contexts

import Foundation
import SharedKernel

// MARK: - SidebarReadModelPort

/// Provides the combined sidebar view of pinned contexts and recents.
///
/// Declared in the domain core; implemented by a projection adapter that
/// assembles `SidebarReadModel` from the repository and active-context state.
/// The domain core never imports SwiftUI or any UI framework.
public protocol SidebarReadModelPort: Sendable {
    /// Fetches the current sidebar read model on demand.
    ///
    /// - Returns: A `SidebarReadModel` combining sorted pins and the recents
    ///   window (with pinned entries excluded from the recents list).
    /// - Throws: `SidebarReadModelError` on storage or projection failure.
    func currentSidebar() async throws -> SidebarReadModel

    /// Returns a stream that emits an updated `SidebarReadModel` each time
    /// pins or recents change.
    ///
    /// - Returns: An `AsyncThrowingStream` that emits continuously until
    ///   cancelled.
    func watchSidebar() -> AsyncThrowingStream<SidebarReadModel, Error>
}

// MARK: - SidebarReadModelError

/// Errors raised by `SidebarReadModelPort` implementations.
public enum SidebarReadModelError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
}

// MARK: - UnimplementedSidebarReadModelPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedSidebarReadModelPort: SidebarReadModelPort {
    public init() {}

    public func currentSidebar() async throws -> SidebarReadModel {
        throw SidebarReadModelError.unimplemented
    }

    public func watchSidebar() -> AsyncThrowingStream<SidebarReadModel, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: SidebarReadModelError.unimplemented)
        }
    }
}
