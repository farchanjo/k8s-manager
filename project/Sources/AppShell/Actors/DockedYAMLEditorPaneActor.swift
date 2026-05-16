// Actors/DockedYAMLEditorPaneActor.swift — app_shell bounded context
// DDD role: DomainService actor — owns docked YAML editor pane state + persistence
// ADR ref: ADR-0064 (inline docked YAML editor pane)

import Foundation
import SharedKernel

// MARK: - DockedYAMLEditorPaneSnapshot

/// Immutable point-in-time snapshot of the docked YAML editor pane state.
///
/// Emitted by ``DockedYAMLEditorPaneActor/stateStream()`` for `@MainActor`
/// observers such as `SidebarCanvasView`. Equatable so views diff and avoid
/// unnecessary redraws.
public struct DockedYAMLEditorPaneSnapshot: Sendable, Equatable {
    /// Full aggregate state at this moment.
    public let state: DockedYAMLEditorPaneState

    /// Convenience: whether the pane is currently open.
    public var isOpen: Bool { state.isOpen }

    /// Convenience: the active draft, or `nil` when the pane is closed.
    public var activeDraft: DockedEditorDraft? { state.activeDraft }

    public init(state: DockedYAMLEditorPaneState) {
        self.state = state
    }
}

// MARK: - DockedYAMLEditorPaneActor

/// Actor that owns the inline docked YAML editor pane lifecycle.
///
/// Responsibilities (per ADR-0064):
/// - Open the pane for a resource, replacing the current draft when one is
///   already open and `isDirty == false`.
/// - Persist the active draft to disk with a 500 ms debounce so unsaved edits
///   survive relaunches.
/// - Restore the draft on cold launch with `isDirty` preserved so the pane
///   re-opens ready for further editing.
/// - Broadcast ``DockedYAMLEditorPaneSnapshot`` to all registered observers.
/// - Enforce the one-pane-at-a-time rule in coordination with the caller
///   (see `DockedEditorPaneOrchestrator` note in ADR-0064).
public actor DockedYAMLEditorPaneActor {

    // MARK: State

    /// Current in-memory aggregate state. `internal` for testing; treat as
    /// read-only from outside the actor (`@testable import AppShell` required).
    var state: DockedYAMLEditorPaneState

    // MARK: Continuations

    private var continuations: [UUID: AsyncStream<DockedYAMLEditorPaneSnapshot>.Continuation] = [:]

    // MARK: Persistence

    private let persistenceURL: URL
    private var persistTask: Task<Void, Never>?

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameter persistenceURL: JSON file for pane state restoration.
    ///   Production callers should pass `ApplicationPaths.dockedYAMLEditorPaneURL`.
    public init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
        self.state = DockedYAMLEditorPaneState()
    }

    // MARK: - Draft lifecycle

    /// Opens the docked editor for `draft`.
    ///
    /// If the pane is already open for a *different* resource and `isDirty == false`,
    /// the existing draft is replaced in-place. If `isDirty == true` the caller is
    /// responsible for presenting the unsaved-changes guard before calling this method.
    ///
    /// If the pane is already open for the *same* resource, this is a no-op — the
    /// caller should scroll the editor to top and move keyboard focus.
    ///
    /// - Parameter draft: The new draft to load.
    /// - Parameter showTerminalBanner: Whether to show the "Terminal sessions are running"
    ///   banner (ADR-0064 §Coexistence).
    public func openDraft(
        _ draft: DockedEditorDraft,
        showTerminalBanner: Bool = false
    ) async {
        if let existing = state.activeDraft, existing.ref == draft.ref,
           existing.clusterId == draft.clusterId {
            return
        }
        state.activeDraft = draft
        state.showTerminalRunningBanner = showTerminalBanner
        broadcast()
        await scheduleSave()
    }

    /// Closes the docked pane, discarding the active draft.
    ///
    /// Callers must present the unsaved-changes guard before invoking this method
    /// when `state.activeDraft?.isDirty == true`.
    public func closeDraft() async {
        state.activeDraft = nil
        state.showTerminalRunningBanner = false
        broadcast()
        await scheduleSave()
    }

    /// Updates the draft text and dirty flag after each editor change.
    ///
    /// - Parameters:
    ///   - text: Current editor content.
    ///   - isDirty: Whether the content differs from the original loaded manifest.
    public func updateDraftText(_ text: String, isDirty: Bool) async {
        guard state.activeDraft != nil else { return }
        state.activeDraft?.draftText = text
        state.activeDraft?.isDirty = isDirty
        broadcast()
        await scheduleSave()
    }

    /// Toggles the diff overlay visibility for the active draft.
    public func toggleDiffOverlay() async {
        guard state.activeDraft != nil else { return }
        state.activeDraft?.isDiffOverlayVisible.toggle()
        broadcast()
    }

    // MARK: - Visibility toggle (ADR-0064 keyboard shortcut)

    /// Toggles the pane visibility. When the pane is open, closes it (discarding
    /// the draft if `isDirty == false`). When it is closed and there is no saved
    /// draft, this is a no-op — opening requires an explicit `openDraft(_:)` call.
    public func toggleVisibility() async {
        guard let draft = state.activeDraft else { return }
        if draft.isDirty { return }
        await closeDraft()
    }

    // MARK: - Pane geometry

    /// Updates the pane height (in points). Clamps to `[200, …]`.
    ///
    /// - Parameter height: New pane height in points.
    public func setPaneHeight(_ height: Double) async {
        let clamped = max(200, height)
        guard clamped != state.paneHeight else { return }
        state.paneHeight = clamped
        broadcast()
        await scheduleSave()
    }

    /// Toggles the fullscreen expansion of the docked pane.
    public func toggleFullscreen() async {
        state.fullscreen.toggle()
        broadcast()
        await scheduleSave()
    }

    // MARK: - Stream

    /// Returns an `AsyncStream` that emits the current snapshot immediately
    /// and on every subsequent mutation.
    public func stateStream() -> AsyncStream<DockedYAMLEditorPaneSnapshot> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.registerContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: - Persistence

    /// Loads saved state from `persistenceURL`. Missing file is first-launch.
    ///
    /// - Throws: `DecodingError` when the file exists but is malformed.
    public func loadFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        let data = try Data(contentsOf: persistenceURL)
        let loaded = try JSONDecoder().decode(DockedYAMLEditorPaneState.self, from: data)
        state = loaded
        broadcast()
    }

    // MARK: - Private helpers

    private func registerContinuation(
        _ continuation: AsyncStream<DockedYAMLEditorPaneSnapshot>.Continuation,
        key: UUID
    ) {
        continuation.yield(DockedYAMLEditorPaneSnapshot(state: state))
        continuations[key] = continuation
    }

    private func removeContinuation(key: UUID) {
        continuations.removeValue(forKey: key)
    }

    private func broadcast() {
        let snapshot = DockedYAMLEditorPaneSnapshot(state: state)
        for cont in continuations.values { cont.yield(snapshot) }
    }

    private func scheduleSave() async {
        persistTask?.cancel()
        let current = state
        let url = persistenceURL
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Self.writeToDisk(state: current, url: url)
        }
    }

    private static func writeToDisk(state: DockedYAMLEditorPaneState, url: URL) async {
        do {
            let data = try JSONEncoder().encode(state)
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let tmp = dir.appendingPathComponent(
                ".\(url.lastPathComponent).tmp",
                isDirectory: false
            )
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            // Persistence failures are non-fatal — state remains in memory.
        }
    }
}
