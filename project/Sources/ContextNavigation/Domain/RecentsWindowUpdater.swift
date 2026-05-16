// Domain/RecentsWindowUpdater.swift — context_navigation bounded context
// DDD role: DomainService
// Narrative ref: domain/narrative.md §Tactical roles (RecentsWindowUpdater)

import Foundation
import SharedKernel

// MARK: - RecentsWindowUpdater

/// Pure domain service: `(window, selectedContextId, clock) -> window`.
///
/// Caps at `window.maxEntries` non-pinned entries. Pinned entries are never
/// pruned. Most-recent entries move to the head of the list.
public enum RecentsWindowUpdater {
    /// Records a new selection in the recents window.
    ///
    /// - Parameters:
    ///   - window: The current recents window.
    ///   - contextId: The context that was just selected.
    ///   - displayName: Human-readable label for the context.
    ///   - clock: Clock used to stamp `lastUsedRFC3339`.
    /// - Returns: Updated window with the entry promoted to the head.
    public static func record(
        in window: RecentContextWindow,
        contextId: ContextId,
        displayName: String,
        clock: any RFC3339Clock
    ) -> RecentContextWindow {
        let rfc3339 = Self.rfc3339(from: clock.now())
        var mutable = window.entries

        let existing = mutable.first { $0.contextId == contextId }
        mutable.removeAll { $0.contextId == contextId }

        let updated = RecentContextEntry(
            contextId: contextId,
            displayName: displayName,
            lastUsedRFC3339: rfc3339,
            useCount: (existing?.useCount ?? 0) + 1,
            pinned: existing?.pinned ?? false
        )
        mutable.insert(updated, at: 0)
        mutable = Self.prune(mutable, maxEntries: window.maxEntries)
        return RecentContextWindow(maxEntries: window.maxEntries, entries: mutable)
    }

    // MARK: - Private helpers

    /// Removes trailing non-pinned entries beyond the cap.
    private static func prune(_ entries: [RecentContextEntry], maxEntries: Int) -> [RecentContextEntry] {
        var nonPinnedCount = 0
        return entries.filter { entry in
            if entry.pinned { return true }
            nonPinnedCount += 1
            return nonPinnedCount <= maxEntries
        }
    }

    private static func rfc3339(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
