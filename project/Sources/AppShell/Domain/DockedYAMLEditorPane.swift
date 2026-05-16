// Domain/DockedYAMLEditorPane.swift — app_shell bounded context
// DDD role: ValueObject — docked YAML editor pane domain model
// ADR ref: ADR-0064 (inline docked YAML editor pane)

import Foundation
import SharedKernel

// MARK: - DockedEditorDraft

/// A single in-progress YAML edit session hosted in the docked pane.
///
/// One draft corresponds to one `#EditorSession` from ADR-0030. Drafts are
/// serialised to `docked-yaml-editor-pane.json` so unsaved edits survive
/// application relaunches.
public struct DockedEditorDraft: Identifiable, Hashable, Sendable, Codable {

    // MARK: Fields

    /// Stable UUID uniquely identifying this draft instance.
    public let id: UUID

    /// Cluster this edit targets.
    public let clusterId: ClusterId

    /// The Kubernetes resource being edited.
    public let ref: ResourceRef

    /// Current editor text (may differ from the server-state manifest).
    public var draftText: String

    /// Whether the draft text differs from the content loaded from the cluster.
    public var isDirty: Bool

    /// Whether the diff overlay is currently shown in the editor.
    public var isDiffOverlayVisible: Bool

    /// Timestamp when this draft was originally created.
    public let openedAt: Date

    // MARK: Init

    public init(
        id: UUID = UUID(),
        clusterId: ClusterId,
        ref: ResourceRef,
        draftText: String,
        isDirty: Bool = false,
        isDiffOverlayVisible: Bool = false,
        openedAt: Date = Date()
    ) {
        self.id = id
        self.clusterId = clusterId
        self.ref = ref
        self.draftText = draftText
        self.isDirty = isDirty
        self.isDiffOverlayVisible = isDiffOverlayVisible
        self.openedAt = openedAt
    }
}

// MARK: - DockedYAMLEditorPaneState

/// Workspace-scoped aggregate persisted to `docked-yaml-editor-pane.json`.
///
/// Owned by ``DockedYAMLEditorPaneActor`` at runtime. Per ADR-0064 only one
/// draft is active at a time (`activeDraftId`). The pane is visible when
/// `activeDraftId` is non-nil.
///
/// Coexistence invariant (ADR-0064 §Coexistence with the bottom-docked terminal
/// pane): only one docked pane is visible per workspace window. The pane actors
/// coordinate via the dependency registry; the view enforces mutual exclusion.
public struct DockedYAMLEditorPaneState: Sendable, Codable, Equatable {

    // MARK: Fields

    /// Schema version for forward-compatible migrations.
    public let schemaVersion: Int

    /// Current pane height in points. Minimum 200 pt (ADR-0064 §Pane chrome).
    public var paneHeight: Double

    /// Whether the pane is expanded to fill the full content area height.
    public var fullscreen: Bool

    /// The single active draft, or `nil` when the pane is closed.
    public var activeDraft: DockedEditorDraft?

    /// Whether a banner should be shown indicating that terminal sessions are
    /// running in the background (ADR-0064 §Coexistence).
    public var showTerminalRunningBanner: Bool

    // MARK: Init

    public init(
        schemaVersion: Int = 1,
        paneHeight: Double = 300,
        fullscreen: Bool = false,
        activeDraft: DockedEditorDraft? = nil,
        showTerminalRunningBanner: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.paneHeight = max(paneHeight, 200)
        self.fullscreen = fullscreen
        self.activeDraft = activeDraft
        self.showTerminalRunningBanner = showTerminalRunningBanner
    }

    // MARK: Derived

    /// The id of the active draft, or `nil` when the pane is closed.
    public var activeDraftId: UUID? { activeDraft?.id }

    /// Whether the pane should be visible (has an active draft).
    public var isOpen: Bool { activeDraft != nil }
}
