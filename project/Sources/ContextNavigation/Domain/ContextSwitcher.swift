// Domain/ContextSwitcher.swift — context_navigation bounded context
// DDD role: DomainService
// Narrative ref: domain/narrative.md §Tactical roles (ContextSwitcher)

import Foundation
import SharedKernel

// MARK: - ActiveContextChanged

/// Domain event emitted when the active context transitions to a new value.
///
/// A selection that targets the already-active context is a no-op and produces
/// no event.
public struct ActiveContextChanged: Hashable, Sendable, Codable {
    /// The previous active context. `nil` on the first selection.
    public let previous: ActiveContext?

    /// The newly active context.
    public let next: ActiveContext

    public init(previous: ActiveContext?, next: ActiveContext) {
        self.previous = previous
        self.next = next
    }
}

// MARK: - ContextSwitcher

/// Pure domain service: `(currentActive, newContextId, clock) -> ActiveContext`.
///
/// Emits `ActiveContextChanged` when the active context actually changes.
/// No-ops when `newContextId` equals the currently active `contextId`.
public enum ContextSwitcher {
    /// Attempts to switch the active context to `newContextId`.
    ///
    /// Returns `(updated, event)` when a real transition occurs, or
    /// `(current, nil)` when `newContextId` is already active.
    ///
    /// - Parameters:
    ///   - current: The current `ActiveContext` singleton.
    ///   - newContextId: The `ContextId` the operator selected.
    ///   - origin: How the selection was triggered.
    ///   - clock: Clock used to stamp `selectedAtRFC3339`.
    /// - Returns: Updated aggregate and optional domain event.
    public static func select(
        current: ActiveContext,
        newContextId: ContextId,
        origin: SelectionOrigin,
        clock: any RFC3339Clock
    ) -> (ActiveContext, ActiveContextChanged?) {
        guard current.contextId != newContextId else {
            return (current, nil)
        }
        let rfc3339 = Self.rfc3339(from: clock.now())
        let next = ActiveContext(
            id: current.id,
            contextId: newContextId,
            selectedAtRFC3339: rfc3339,
            selectedBy: origin
        )
        return (next, ActiveContextChanged(previous: current, next: next))
    }

    // MARK: - Private helpers

    private static func rfc3339(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
