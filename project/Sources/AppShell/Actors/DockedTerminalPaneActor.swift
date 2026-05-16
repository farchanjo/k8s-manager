// Actors/DockedTerminalPaneActor.swift — app_shell bounded context
// DDD role: DomainService actor — owns docked terminal pane state + persistence
// ADR ref: ADR-0057 (bottom-docked terminal pane with node-debug shell integration)

import Foundation
import SharedKernel

// MARK: - DockedTerminalPaneSnapshot

/// Immutable point-in-time snapshot of the docked terminal pane state.
///
/// Emitted by ``DockedTerminalPaneActor/stateStream()`` for `@MainActor`
/// observers such as `SidebarCanvasView`. Equatable so views diff and avoid
/// unnecessary redraws.
public struct DockedTerminalPaneSnapshot: Sendable, Equatable {
    /// Current persisted + in-memory state.
    public let state: DockedTerminalPaneState

    /// Convenience: whether the pane is visible (has at least one tab).
    public var isOpen: Bool { state.isOpen }

    /// Convenience: ordered tab list.
    public var tabs: [DockedTerminalTab] { state.tabs }

    /// Convenience: the focused tab id.
    public var activeTabId: UUID? { state.activeTabId }

    public init(state: DockedTerminalPaneState) {
        self.state = state
    }
}

// MARK: - DockedTerminalPaneActor

/// Actor that owns the lifecycle of the bottom-docked terminal pane.
///
/// Responsibilities (per ADR-0057):
/// - Open / close / switch docked terminal tabs.
/// - Enforce the at-most-one-nodeDebug-per-node-per-cluster invariant.
/// - Update `connectionState` on each tab as the backing `TerminalSessionActor` transitions.
/// - Persist state to disk with a 500 ms debounce (atomic tmp → rename write).
/// - Restore state on launch: all tabs in `.closed`; no actor auto-started.
/// - Broadcast ``DockedTerminalPaneSnapshot`` to all registered observers.
public actor DockedTerminalPaneActor {

    // MARK: State

    /// Current in-memory aggregate state. `internal` for testing; treat as read-only
    /// from outside the actor (`@testable import AppShell` required).
    var state: DockedTerminalPaneState

    // MARK: Continuations

    private var continuations: [UUID: AsyncStream<DockedTerminalPaneSnapshot>.Continuation] = [:]

    // MARK: Persistence

    private let persistenceURL: URL
    private var persistTask: Task<Void, Never>?

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameter persistenceURL: JSON file for docked-pane state restoration.
    ///   Production callers should pass `ApplicationPaths.dockedTerminalPaneURL`.
    public init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
        self.state = DockedTerminalPaneState()
    }

    // MARK: - Tab lifecycle

    /// Opens a new docked terminal tab, or focuses an existing one when the
    /// same node/pod combination is already present.
    ///
    /// Enforces the at-most-one-nodeDebug-per-node-per-cluster invariant:
    /// a duplicate `nodeDebug` request brings the existing tab to focus.
    ///
    /// - Parameter tab: The tab descriptor to open.
    public func openTab(_ tab: DockedTerminalTab) async {
        if let dup = findDuplicate(of: tab) {
            state.activeTabId = dup.id
            broadcast()
            return
        }
        state.tabs.append(tab)
        state.activeTabId = tab.id
        broadcast()
        await scheduleSave()
    }

    /// Closes the tab with `id`. Focuses the preceding tab when possible,
    /// otherwise focuses the new tail. Sets `activeTabId` to `nil` when the
    /// last tab is removed.
    ///
    /// - Parameter id: The UUID of the tab to remove.
    public func closeTab(_ id: UUID) async {
        guard let idx = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs.remove(at: idx)
        if state.activeTabId == id {
            state.activeTabId = state.tabs.isEmpty
                ? nil
                : state.tabs[max(0, idx - 1)].id
        }
        broadcast()
        await scheduleSave()
    }

    /// Focuses the tab with the given `id`. No-op when absent.
    ///
    /// - Parameter id: UUID of the tab to focus.
    public func focusTab(_ id: UUID) async {
        guard state.tabs.contains(where: { $0.id == id }) else { return }
        state.activeTabId = id
        broadcast()
    }

    /// Updates the `connectionState` of an existing tab. Used by the view model
    /// when it receives lifecycle events from `TerminalSessionActor`.
    ///
    /// - Parameters:
    ///   - id: The UUID of the tab to update.
    ///   - connectionState: The new lifecycle state.
    public func updateConnectionState(tabId id: UUID, connectionState: TerminalConnectionState) async {
        guard let idx = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs[idx].connectionState = connectionState
        broadcast()
        await scheduleSave()
    }

    /// Links a `TerminalSessionActor` id to a tab (set when a session starts).
    ///
    /// - Parameters:
    ///   - tabId: The docked-tab UUID.
    ///   - actorId: The `TerminalSessionActor` instance id.
    public func assignSessionActor(tabId: UUID, actorId: UUID) async {
        guard let idx = state.tabs.firstIndex(where: { $0.id == tabId }) else { return }
        state.tabs[idx].sessionActorId = actorId
        broadcast()
        await scheduleSave()
    }

    // MARK: - Visibility toggle

    /// Toggles the pane open/closed. When all tabs are closed the pane hides
    /// automatically; this method is used by the keyboard shortcut to open
    /// the pane when it is hidden (or close it when no useful action follows).
    ///
    /// Specifically: if the pane has tabs but is not showing (edge case during
    /// animation), the active tab is brought to focus. If the pane has no tabs,
    /// this is a no-op — opening requires an explicit `openTab(_:)` call.
    public func toggleVisibility() async {
        guard !state.tabs.isEmpty else { return }
        // The pane is already visible if tabs are present; focus the active tab.
        broadcast()
    }

    // MARK: - Pane geometry

    /// Updates the pane height (in points). Clamps to `[120, …]`; the upper
    /// bound is enforced by the caller who knows the content-area height.
    ///
    /// - Parameter height: New pane height in points (must be >= 120).
    public func setPaneHeight(_ height: Double) async {
        let clamped = max(120, height)
        guard clamped != state.paneHeight else { return }
        state.paneHeight = clamped
        broadcast()
        await scheduleSave()
    }

    /// Toggles the fullscreen state of the docked pane.
    public func toggleFullscreen() async {
        state.fullscreen.toggle()
        broadcast()
        await scheduleSave()
    }

    // MARK: - Stream

    /// Returns an `AsyncStream` that emits the current snapshot immediately
    /// and on every subsequent mutation.
    public func stateStream() -> AsyncStream<DockedTerminalPaneSnapshot> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.registerContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: - Persistence

    /// Loads saved state from `persistenceURL`. All restored tabs have their
    /// `connectionState` forced to `.closed` per ADR-0057 §Persistence.
    /// Missing file is treated as first-launch (default empty state).
    ///
    /// - Throws: `DecodingError` when the file exists but is malformed.
    public func loadFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        let data = try Data(contentsOf: persistenceURL)
        var loaded = try JSONDecoder().decode(DockedTerminalPaneState.self, from: data)
        // Invariant: all restored tabs start as closed (no actor auto-start).
        for i in loaded.tabs.indices {
            loaded.tabs[i].connectionState = .closed
            loaded.tabs[i].sessionActorId = nil
        }
        state = loaded
        broadcast()
    }

    // MARK: - Private helpers

    private func findDuplicate(of tab: DockedTerminalTab) -> DockedTerminalTab? {
        switch tab.kind {
        case .nodeDebug:
            return state.tabs.first {
                $0.kind == .nodeDebug
                    && $0.clusterId == tab.clusterId
                    && $0.targetNodeName == tab.targetNodeName
            }
        case .podExec, .containerExec:
            return state.tabs.first {
                $0.kind == tab.kind
                    && $0.clusterId == tab.clusterId
                    && $0.targetPodName == tab.targetPodName
                    && $0.targetPodNamespace == tab.targetPodNamespace
            }
        }
    }

    private func registerContinuation(
        _ continuation: AsyncStream<DockedTerminalPaneSnapshot>.Continuation,
        key: UUID
    ) {
        continuation.yield(DockedTerminalPaneSnapshot(state: state))
        continuations[key] = continuation
    }

    private func removeContinuation(key: UUID) {
        continuations.removeValue(forKey: key)
    }

    private func broadcast() {
        let snapshot = DockedTerminalPaneSnapshot(state: state)
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

    private static func writeToDisk(state: DockedTerminalPaneState, url: URL) async {
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
