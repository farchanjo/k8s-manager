// Domain/RecentContext.swift — context_navigation bounded context
// DDD role: ReadModel, ValueObject
// CUE source: docs/arch/contexts/context_navigation/schemas/recent_context.cue

import Foundation
import SharedKernel

// MARK: - RecentContextEntry

/// One row in the most-recently-used list of Kubernetes contexts.
///
/// Mirrors `#RecentContextEntry` from `recent_context.cue`. Immutable after
/// construction. The full window is a `ReadModel` materialised from
/// `UserDefaults`; no business invariant is authoritative here.
public struct RecentContextEntry: Hashable, Sendable, Codable {
    /// Shared-kernel identifier of the context.
    public let contextId: ContextId

    /// Human-readable display name shown in the sidebar.
    public let displayName: String

    /// RFC 3339 timestamp of the most recent selection.
    public let lastUsedRFC3339: String

    /// Number of times this context has been selected. Minimum 1.
    public let useCount: Int

    /// When `true`, the entry is pinned and exempt from recents pruning.
    public let pinned: Bool

    public init(
        contextId: ContextId,
        displayName: String,
        lastUsedRFC3339: String,
        useCount: Int,
        pinned: Bool = false
    ) {
        self.contextId = contextId
        self.displayName = displayName
        self.lastUsedRFC3339 = lastUsedRFC3339
        self.useCount = max(1, useCount)
        self.pinned = pinned
    }
}

// MARK: - RecentContextWindow

/// Bounded most-recently-used list maintained by the `context_navigation`
/// aggregate.
///
/// Mirrors `#RecentContextWindow` from `recent_context.cue`. Ordered
/// most-recent first. Holds at most `maxEntries` non-pinned entries; pinned
/// entries are exempt from pruning. `maxEntries` is clamped to [8, 64];
/// default is 32.
public struct RecentContextWindow: Hashable, Sendable, Codable {
    /// Maximum number of non-pinned entries before tail pruning occurs.
    /// Clamped to [8, 64].
    public let maxEntries: Int

    /// Ordered entries, most-recent first.
    public let entries: [RecentContextEntry]

    public init(
        maxEntries: Int = 32,
        entries: [RecentContextEntry] = []
    ) {
        self.maxEntries = min(64, max(8, maxEntries))
        self.entries = entries
    }
}

// MARK: - PinnedContext

/// Value object capturing one operator-pinned Kubernetes context.
///
/// Mirrors `#PinnedContext` from `recent_context.cue`. Pins survive
/// application restarts and kubeconfig reloads (as long as the underlying
/// context still resolves to the same `ContextId`).
public struct PinnedContext: Hashable, Sendable, Codable {
    /// Shared-kernel identifier of the pinned context.
    public let contextId: ContextId

    /// RFC 3339 timestamp when the operator pinned this context.
    public let pinnedAtRFC3339: String

    /// Operator-chosen ordering in the pinned section of the sidebar.
    /// Lower values sort first. Minimum 0.
    public let displayOrder: Int

    public init(
        contextId: ContextId,
        pinnedAtRFC3339: String,
        displayOrder: Int
    ) {
        self.contextId = contextId
        self.pinnedAtRFC3339 = pinnedAtRFC3339
        self.displayOrder = max(0, displayOrder)
    }
}
