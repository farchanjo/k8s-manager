// Domain/DockedTerminalPane.swift — app_shell bounded context
// DDD role: ValueObject — docked terminal pane domain model
// ADR ref: ADR-0057 (bottom-docked terminal pane with node-debug shell integration)
// CUE source: docs/arch/contexts/app_shell/schemas/docked_terminal_pane.cue

import Foundation
import SharedKernel

// MARK: - DockedPanePosition

/// Layout position for a docked pane. v1 supports bottom only.
///
/// Reserved for extension — a left-side or right-side docked terminal
/// is a possible future enhancement (ADR-0057 §Decision outcome).
public enum DockedPanePosition: String, Hashable, Sendable, Codable {
    /// Pane is anchored at the bottom of the content area. The only legal
    /// value in v1; additional cases will be added by a future ADR.
    case bottom
}

// MARK: - DockedTerminalKind

/// Discriminates the kind of PTY session hosted in one docked terminal tab.
///
/// Each kind maps to a distinct entry sequence in `TerminalSessionActor`
/// and to distinct UI affordances: label format and connection-banner text.
public enum DockedTerminalKind: String, Hashable, Sendable, Codable {
    /// Pod exec session opened from a Pod row or a Pod detail drawer.
    case podExec
    /// `kubectl debug node` session via an ephemeral debug Pod.
    case nodeDebug
    /// Ad-hoc container exec opened via the docked-pane `+` button.
    case containerExec
}

// MARK: - TerminalConnectionState

/// Lifecycle state of one docked terminal tab, mirroring `SessionStatus`
/// from `TerminalSessionActor`.
///
/// Used to drive the per-tab indicator dot (green / amber / red) and the
/// connection banner inside the PTY viewport. State transitions are always
/// forward except `error`, which is terminal:
/// ```
/// opening → open → closing → closed
/// opening → error
/// open    → error
/// ```
public enum TerminalConnectionState: String, Hashable, Sendable, Codable {
    /// WebSocket handshake or debug-Pod creation is in flight.
    case opening
    /// Live PTY — bidirectional I/O streaming is active.
    case open
    /// Cooperative close dispatched; final frames are being flushed.
    case closing
    /// Session ended cleanly. Banner shows "Session closed" + Reopen.
    case closed
    /// Session failed. Banner shows error message + Retry.
    case error
}

// MARK: - DockedTerminalTab

/// One tab in the docked terminal pane tab bar.
///
/// Each instance represents one `TerminalSessionActor` session. Tabs are
/// persisted (without PTY output buffers per ADR-0017 §Decision drivers) to
/// allow cold-launch restore in the `closed` state.
///
/// `sessionActorId` is not persisted; actors are not re-hydrated after
/// launch. The operator must tap "Reopen" to start a new `TerminalSessionActor`.
public struct DockedTerminalTab: Identifiable, Hashable, Sendable, Codable {

    // MARK: Fields

    /// Stable UUID uniquely identifying this docked-tab instance.
    /// Generated at open time; never reused.
    public let id: UUID

    /// Session kind determining entry-path and UI label format.
    public let kind: DockedTerminalKind

    /// The `id` of the backing `TerminalSessionActor` instance.
    /// `nil` after cold-launch restore until the operator reopens the session.
    public var sessionActorId: UUID?

    /// Human-readable label shown in the tab bar.
    /// Examples: `"Node: worker-01"`, `"Pod: api-server-abc12"`.
    /// Max 64 characters (enforced by CUE schema).
    public let label: String

    /// The cluster this session belongs to.
    public let clusterId: ClusterId

    /// Node name targeted by `nodeDebug` sessions. `nil` for other kinds.
    public let targetNodeName: String?

    /// Namespace of the targeted Pod for `podExec` and `containerExec` sessions.
    public let targetPodNamespace: String?

    /// Name of the targeted Pod for `podExec` and `containerExec` sessions.
    public let targetPodName: String?

    /// Container name inside the target Pod. Required for `containerExec`;
    /// optional for `podExec`; absent for `nodeDebug`.
    public let targetContainerName: String?

    /// Current lifecycle state, mirrored from the backing `TerminalSessionActor`.
    /// Restored tabs always start as `.closed` on cold launch.
    public var connectionState: TerminalConnectionState

    /// RFC 3339 timestamp of when this tab was originally opened.
    public let openedAt: Date

    // MARK: Init

    /// Creates a new docked terminal tab with all fields.
    public init(
        id: UUID = UUID(),
        kind: DockedTerminalKind,
        sessionActorId: UUID? = nil,
        label: String,
        clusterId: ClusterId,
        targetNodeName: String? = nil,
        targetPodNamespace: String? = nil,
        targetPodName: String? = nil,
        targetContainerName: String? = nil,
        connectionState: TerminalConnectionState = .opening,
        openedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sessionActorId = sessionActorId
        self.label = String(label.prefix(64))
        self.clusterId = clusterId
        self.targetNodeName = targetNodeName
        self.targetPodNamespace = targetPodNamespace
        self.targetPodName = targetPodName
        self.targetContainerName = targetContainerName
        self.connectionState = connectionState
        self.openedAt = openedAt
    }
}

// MARK: - DockedTerminalPaneState

/// Workspace-scoped aggregate persisted to `docked-terminal-pane.json`.
///
/// Owned by ``DockedTerminalPaneActor`` at runtime. Restored on cold launch;
/// the pane slides up only when `tabs` is non-empty.
///
/// Invariants enforced by `DockedTerminalPaneActor`:
/// - `activeTabId`, when set, always refers to a tab in `tabs`.
/// - On cold launch every restored tab has `connectionState == .closed`.
/// - `paneHeight` is clamped to `[120, contentAreaHeight × 0.8]` by the
///   actor; the schema only enforces the absolute floor (120 pt).
public struct DockedTerminalPaneState: Sendable, Codable, Equatable {

    // MARK: Fields

    /// Schema version enabling forward-compatible migrations.
    public let schemaVersion: Int

    /// Current pane height in points. Minimum 120 pt; clamped by the actor.
    public var paneHeight: Double

    /// Whether the pane is expanded to fill the full content area height.
    public var fullscreen: Bool

    /// Ordered list of docked tabs (left-to-right, most recently opened rightmost).
    public var tabs: [DockedTerminalTab]

    /// `id` of the focused tab. `nil` when `tabs` is empty.
    public var activeTabId: UUID?

    // MARK: Init

    /// Creates a default empty state suitable for first-launch.
    public init(
        schemaVersion: Int = 1,
        paneHeight: Double = 240,
        fullscreen: Bool = false,
        tabs: [DockedTerminalTab] = [],
        activeTabId: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.paneHeight = max(paneHeight, 120)
        self.fullscreen = fullscreen
        self.tabs = tabs
        self.activeTabId = activeTabId
    }

    // MARK: Derived

    /// Whether the pane should be visible (has at least one tab).
    public var isOpen: Bool { !tabs.isEmpty }
}
