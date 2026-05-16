// Domain/NavigationHistory.swift — app_shell bounded context
// DDD role: Value object (NavigationEntry), Enum (NavigationEntryKind)
// ADR ref: ADR-0065 (Navigation history stack — back/forward within tab)

import CoreGraphics
import Foundation
import SharedKernel

// MARK: - NavigationEntryKind

/// Discriminant for the kind of view that generated a navigation event.
///
/// Mirrors `DocumentTab` case taxonomy from ADR-0050. Terminal-session entries
/// are recorded only for the open/close events, not for in-session interactions.
public enum NavigationEntryKind: String, Sendable, Codable, Hashable {
    case resourceList
    case resourceDetail
    case clusterOverview
    case helmReleases
    case helmDetail
    case events
    case terminalSession
}

// MARK: - NavigationEntry

/// Immutable value object representing a single navigation step.
///
/// Recorded onto `NavigationHistoryActor` whenever the operator navigates
/// to a new view (resource list, resource detail, or cross-tab switch).
/// All fields are `Sendable` so the struct can cross actor boundaries freely.
///
/// Per ADR-0065 the `id` field doubles as a deduplication key: if a candidate
/// entry's stable identity (`clusterId + tabId + kind + namespace +
/// selectedResourceName + drawerSectionAnchor`) matches the current cursor
/// entry, the push is suppressed.
public struct NavigationEntry: Sendable, Identifiable, Codable, Equatable {

    // MARK: Stored properties

    /// Unique identifier (UUIDv4 in practice; ADR-0065 notes UUIDv7 intent).
    public let id: String
    /// Wall-clock time of the navigation event.
    public let timestamp: Date
    /// The cluster active at the time of navigation.
    public let clusterId: String
    /// The `DocumentTab.tabId` active at the time of navigation.
    public let tabId: String
    /// Kind of view that generated the entry.
    public let kind: NavigationEntryKind
    /// Active namespace filter, `nil` for cluster-scoped views.
    public let namespace: String?
    /// Name of the selected resource row, `nil` for list-level navigation.
    public let selectedResourceName: String?
    /// Scroll anchor of the detail drawer section in focus.
    public let drawerSectionAnchor: String?
    /// Vertical scroll offset of the content list at navigation time.
    public let viewportScrollOffset: CGFloat

    // MARK: Init

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        clusterId: String,
        tabId: String,
        kind: NavigationEntryKind,
        namespace: String? = nil,
        selectedResourceName: String? = nil,
        drawerSectionAnchor: String? = nil,
        viewportScrollOffset: CGFloat = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.clusterId = clusterId
        self.tabId = tabId
        self.kind = kind
        self.namespace = namespace
        self.selectedResourceName = selectedResourceName
        self.drawerSectionAnchor = drawerSectionAnchor
        self.viewportScrollOffset = viewportScrollOffset
    }

    // MARK: Stable identity for deduplication

    /// Returns `true` if `candidate` would duplicate the current entry.
    ///
    /// Scroll offset and timestamp are intentionally excluded from the comparison
    /// so that a re-visit to the same resource with a different scroll position
    /// is still suppressed (it would be the same logical location).
    public func isDuplicate(of candidate: NavigationEntry) -> Bool {
        clusterId == candidate.clusterId &&
        tabId == candidate.tabId &&
        kind == candidate.kind &&
        namespace == candidate.namespace &&
        selectedResourceName == candidate.selectedResourceName &&
        drawerSectionAnchor == candidate.drawerSectionAnchor
    }
}

// MARK: - NavigationHistorySnapshot

/// Immutable snapshot of `NavigationHistoryActor` state for `@MainActor` observers.
///
/// Emitted by `NavigationHistoryActor.stateStream()` so toolbar buttons can
/// reactively enable/disable without polling the actor.
public struct NavigationHistorySnapshot: Sendable, Equatable {
    /// Whether the back arrow should be enabled.
    public let canGoBack: Bool
    /// Whether the forward arrow should be enabled.
    public let canGoForward: Bool
    /// Number of entries in the deque.
    public let entryCount: Int
    /// Zero-based index of the current cursor position.
    public let cursorIndex: Int

    public init(canGoBack: Bool, canGoForward: Bool, entryCount: Int, cursorIndex: Int) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.entryCount = entryCount
        self.cursorIndex = cursorIndex
    }

    /// Snapshot representing an empty history.
    public static let empty = NavigationHistorySnapshot(
        canGoBack: false,
        canGoForward: false,
        entryCount: 0,
        cursorIndex: -1
    )
}
