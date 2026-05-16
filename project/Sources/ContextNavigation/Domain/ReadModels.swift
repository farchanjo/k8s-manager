// Domain/ReadModels.swift — context_navigation bounded context
// DDD role: ReadModel
// Narrative ref: domain/narrative.md §Read models exposed to other contexts

import Foundation
import SharedKernel

// MARK: - ActiveContextReadModel

/// What to render in the title bar and the menu bar.
///
/// Consumed by `app_shell`. Produced by the `ContextRepositoryPort`
/// query path.
public struct ActiveContextReadModel: Hashable, Sendable, Codable {
    /// Currently active context identifier. `nil` when no context has been
    /// selected since application launch.
    public let contextId: ContextId?

    /// Human-readable display name resolved from the cluster connectivity
    /// read model. `nil` when no context is active.
    public let displayName: String?

    /// RFC 3339 timestamp of the most recent selection. `nil` when no context
    /// is active.
    public let selectedAtRFC3339: String?

    /// How the current context was chosen.
    public let selectedBy: SelectionOrigin?

    public init(
        contextId: ContextId? = nil,
        displayName: String? = nil,
        selectedAtRFC3339: String? = nil,
        selectedBy: SelectionOrigin? = nil
    ) {
        self.contextId = contextId
        self.displayName = displayName
        self.selectedAtRFC3339 = selectedAtRFC3339
        self.selectedBy = selectedBy
    }
}

// MARK: - SidebarReadModel

/// Combined view of pinned contexts and recents exposed to `app_shell`.
///
/// The sidebar renders pinned entries (sorted by `displayOrder`) above the
/// recents window (ordered most-recent first, pinned entries excluded to
/// avoid duplication).
public struct SidebarReadModel: Hashable, Sendable, Codable {
    /// Pinned contexts sorted ascending by `PinnedContext.displayOrder`.
    public let pinned: [PinnedContext]

    /// Recent context entries ordered most-recent first. Pinned entries that
    /// also appear in `recents` are NOT duplicated here.
    public let recents: [RecentContextEntry]

    public init(
        pinned: [PinnedContext] = [],
        recents: [RecentContextEntry] = []
    ) {
        self.pinned = pinned.sorted { $0.displayOrder < $1.displayOrder }
        self.recents = recents
    }
}
