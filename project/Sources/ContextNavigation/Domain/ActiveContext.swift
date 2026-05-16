// Domain/ActiveContext.swift — context_navigation bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/context_navigation/schemas/active_context.cue

import Foundation
import SharedKernel

// MARK: - SelectionOrigin

/// Describes how the active context was chosen.
///
/// Mirrors the `selectedBy` discriminant from `active_context.cue`.
public enum SelectionOrigin: String, Hashable, Sendable, Codable, CaseIterable {
    /// Operator made an explicit selection from the UI.
    case user

    /// Application restored the last-used context at launch.
    case restored

    /// Application defaulted to the kubeconfig-level `current-context`
    /// because the last-used value was no longer valid.
    case fallback
}

// MARK: - ActiveContext

/// Singleton aggregate root recording which Kubernetes context the operator
/// is currently looking at.
///
/// Mirrors `#ActiveContext` from `active_context.cue`. At most one
/// `ActiveContext` exists per application run. `contextId` is absent during
/// the brief window before the first selection is made.
public struct ActiveContext: Hashable, Sendable, Codable {
    /// UUIDv7 generated when the aggregate is first materialised. Stable for
    /// the lifetime of the process; not persisted across launches.
    public let id: UUID

    /// Shared-kernel identifier of the currently active Kubernetes context.
    /// `nil` until the first selection has been made.
    public let contextId: ContextId?

    /// RFC 3339 timestamp of the most recent selection. Used by
    /// `RecentContextWindow` to order entries.
    public let selectedAtRFC3339: String?

    /// How the active context was chosen.
    public let selectedBy: SelectionOrigin?

    public init(
        id: UUID = UUIDv7.generate(),
        contextId: ContextId? = nil,
        selectedAtRFC3339: String? = nil,
        selectedBy: SelectionOrigin? = nil
    ) {
        self.id = id
        self.contextId = contextId
        self.selectedAtRFC3339 = selectedAtRFC3339
        self.selectedBy = selectedBy
    }
}
