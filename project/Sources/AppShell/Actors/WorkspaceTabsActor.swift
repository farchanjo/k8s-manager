// Actors/WorkspaceTabsActor.swift — app_shell bounded context
// DDD role: Domain actor — workspace-scoped tab state manager
// ADR ref: ADR-0054 (Welcome tab and cluster-acquisition entry surface)

import Foundation
import SharedKernel

// MARK: - WorkspaceTabsSnapshot

/// Immutable point-in-time snapshot of the workspace-scoped tab state.
///
/// Emitted by ``WorkspaceTabsActor/stateStream()`` for `@MainActor` observers
/// such as `TabBarView` when it renders workspace tabs alongside per-cluster
/// tabs.
public struct WorkspaceTabsSnapshot: Sendable, Equatable {
    /// Ordered list of workspace-scoped tabs as displayed in the tab bar.
    public let tabs: [DocumentTab]
    /// Id of the active workspace tab, or `nil` when no workspace tab is focused.
    public let activeTabId: TabId?

    public init(tabs: [DocumentTab], activeTabId: TabId?) {
        self.tabs = tabs
        self.activeTabId = activeTabId
    }
}

// MARK: - WorkspaceTabsActor

/// Actor that owns the workspace-scoped tab list — currently the persistent
/// Welcome tab and any future workspace-level surfaces (What's New, global
/// Diagnostics, etc.).
///
/// Responsibilities (per ADR-0054):
/// - Guarantee a single `.welcome` instance always exists at position 0.
/// - Injects the Welcome tab on first launch and on migration from a payload
///   that does not contain one.
/// - Persist to a single workspace-scoped JSON file under the application
///   support directory, distinct from per-cluster `open-tabs.json` files.
/// - Enforce the single-instance invariant: any caller trying to open a second
///   `.welcome` tab will be redirected to focus the existing instance.
/// - Broadcast `WorkspaceTabsSnapshot` to all stream observers.
public actor WorkspaceTabsActor {

    // MARK: Public state

    /// Ordered list of workspace tabs. Welcome is always at index 0.
    public private(set) var tabs: [DocumentTab] = [.welcome]

    /// Id of the currently focused workspace tab.
    public private(set) var activeTabId: TabId?

    // MARK: Private state

    /// Live `AsyncStream` continuations for `stateStream()` subscribers.
    private var continuations: [UUID: AsyncStream<WorkspaceTabsSnapshot>.Continuation] = [:]

    /// Debounce task for the 500 ms persistence window (parity with OpenTabsActor).
    private var persistTask: Task<Void, Never>?

    /// Canonical persistence URL for the workspace tab payload.
    private let persistenceURL: URL

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameter persistenceURL: JSON file location for workspace-tab state
    ///   restoration. Production callers should pass
    ///   `ApplicationPaths.workspaceStateRoot.appendingPathComponent("workspace-tabs.json")`.
    public init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
        self.activeTabId = DocumentTab.welcome.id
    }

    // MARK: Tab lifecycle

    /// Opens `tab` in the workspace tab list, or focuses an existing instance.
    ///
    /// Per ADR-0054 the workspace tab list enforces single-instance for the
    /// `.welcome` kind. Any other workspace tab kinds added in the future
    /// also follow the dedup rule by `TabId`.
    public func openTab(_ tab: DocumentTab) async {
        guard tab.isWorkspaceScoped else { return }
        if let existing = tabs.first(where: { $0.id == tab.id }) {
            activeTabId = existing.id
            broadcast()
            return
        }
        tabs.append(tab)
        activeTabId = tab.id
        broadcast()
        await scheduleSave()
    }

    /// Focuses the workspace tab identified by `id`. No-op if `id` is absent.
    public func focusTab(_ id: TabId) async {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        broadcast()
    }

    /// Convenience that focuses the persistent Welcome tab.
    ///
    /// Used by the command-palette entry "Go to Welcome tab" and by the
    /// `⌘⇧W` keyboard shortcut.
    public func focusWelcome() async {
        await focusTab(DocumentTab.welcome.id)
    }

    /// Whether the workspace currently contains a Welcome tab instance.
    public var containsWelcome: Bool {
        tabs.contains { if case .welcome = $0 { return true } else { return false } }
    }

    /// Ensures the Welcome tab exists at position 0. Called by `loadFromDisk`
    /// to recover from a payload that predates the Welcome tab feature.
    public func ensureWelcomePresent() {
        if !containsWelcome {
            tabs.insert(.welcome, at: 0)
            if activeTabId == nil { activeTabId = DocumentTab.welcome.id }
            broadcast()
        }
    }

    // MARK: Stream

    /// Returns an `AsyncStream` that emits the current snapshot immediately and
    /// on every subsequent mutation.
    public func stateStream() -> AsyncStream<WorkspaceTabsSnapshot> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.registerContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: Persistence

    /// Loads the saved workspace tab state from `persistenceURL`. If the file
    /// is absent the actor keeps its default state (Welcome at position 0).
    /// If the payload is present but lacks a Welcome entry, the Welcome tab is
    /// injected at position 0 to satisfy the ADR-0054 invariant.
    ///
    /// - Throws: `DecodingError` if the payload format is invalid. I/O errors
    ///   for missing files are swallowed because absence is a valid state.
    public func loadFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
            ensureWelcomePresent()
            return
        }
        let data = try Data(contentsOf: persistenceURL)
        let payload = try JSONDecoder().decode(PersistedPayload.self, from: data)
        tabs = payload.tabs
        activeTabId = payload.activeTabId
        ensureWelcomePresent()
        broadcast()
    }

    /// Schedules an atomic disk write debounced to 500 ms.
    private func scheduleSave() async {
        persistTask?.cancel()
        let snapshot = PersistedPayload(tabs: tabs, activeTabId: activeTabId)
        let url = persistenceURL
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Self.writeToDisk(payload: snapshot, url: url)
        }
    }

    // MARK: Private helpers

    private func registerContinuation(
        _ continuation: AsyncStream<WorkspaceTabsSnapshot>.Continuation,
        key: UUID
    ) {
        continuation.yield(currentSnapshot)
        continuations[key] = continuation
    }

    private func removeContinuation(key: UUID) {
        continuations.removeValue(forKey: key)
    }

    private func broadcast() {
        let snapshot = currentSnapshot
        for cont in continuations.values { cont.yield(snapshot) }
    }

    private var currentSnapshot: WorkspaceTabsSnapshot {
        WorkspaceTabsSnapshot(tabs: tabs, activeTabId: activeTabId)
    }

    // MARK: Static I/O (nonisolated)

    private static func writeToDisk(payload: PersistedPayload, url: URL) async {
        do {
            let data = try JSONEncoder().encode(payload)
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
            // Persistence failures are non-fatal — tabs remain in memory.
        }
    }
}

// MARK: - PersistedPayload

/// Codable envelope stored in `workspace-tabs.json`.
private struct PersistedPayload: Codable, Sendable {
    let tabs: [DocumentTab]
    let activeTabId: TabId?
}
