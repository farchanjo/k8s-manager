// Actors/OpenTabsActor.swift — app_shell bounded context
// DDD role: Domain actor — open-tab state manager + state restoration
// ADR ref: ADR-0050 (resource navigation taxonomy + tab system)

import Foundation
import SharedKernel

// MARK: - OpenTabsSnapshot

/// Immutable point-in-time snapshot of the open-tabs state.
///
/// Emitted by `OpenTabsActor.stateStream()` for `@MainActor` observers
/// such as `TabBarViewModel`. Equatable so views can diff and avoid
/// unnecessary redraws.
public struct OpenTabsSnapshot: Sendable, Equatable {
    /// Ordered list of open tabs as displayed in the tab bar.
    public let tabs: [DocumentTab]
    /// Id of the currently focused tab, or `nil` when no tab is open.
    public let activeTabId: TabId?

    public init(tabs: [DocumentTab], activeTabId: TabId?) {
        self.tabs = tabs
        self.activeTabId = activeTabId
    }
}

// MARK: - OpenTabsActor

/// Actor that owns the lifecycle of open document tabs for a single cluster.
///
/// Responsibilities (per ADR-0050):
/// - Open / focus / close tabs with deduplication by `TabId`.
/// - Maintain an ordered `tabs` array and a `activeTabId` pointer.
/// - Register background `Task`s (watchers) per tab and cancel them on close.
/// - Persist state to disk with a 500 ms debounce (atomic write: tmp → rename).
/// - Restore state from disk on launch via `loadFromDisk()`.
/// - Broadcast `OpenTabsSnapshot` to all registered `AsyncStream` observers.
///
/// One `OpenTabsActor` should be created per cluster that has at least one tab
/// open. The composition root owns the actor's lifetime.
public actor OpenTabsActor {

    // MARK: Public state

    /// Ordered list of open tabs. Index 0 is the leftmost chip.
    public private(set) var tabs: [DocumentTab] = []

    /// Id of the currently focused tab.
    public private(set) var activeTabId: TabId?

    // MARK: Private state

    /// Background tasks keyed by tab — cancelled when the tab closes.
    private var watcherTasks: [TabId: Task<Void, Never>] = [:]

    /// Live `AsyncStream` continuations for `stateStream()` subscribers.
    private var continuations: [UUID: AsyncStream<OpenTabsSnapshot>.Continuation] = [:]

    /// Debounce task for the 500 ms persistence window (ADR-0050).
    private var persistTask: Task<Void, Never>?

    /// Canonical persistence URL for this actor instance.
    private let persistenceURL: URL

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameter persistenceURL: JSON file location for state restoration.
    ///   Production callers should pass
    ///   `ApplicationPaths.clusterStateRoot
    ///       .appendingPathComponent("<clusterId>/open-tabs.json")`.
    public init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
    }

    // MARK: Tab lifecycle

    /// Opens `tab`, or focuses it if an identical tab (same `id`) is already open.
    ///
    /// Per ADR-0050 deduplication rule: `TabId` identity is derived from the
    /// tab's structural properties (cluster + kind + namespace + name), so calling
    /// `openTab(.overview(clusterId: x))` twice only focuses the existing tab.
    public func openTab(_ tab: DocumentTab) async {
        if let existing = tabs.first(where: { $0.id == tab.id }) {
            await focusTab(existing.id)
            return
        }
        tabs.append(tab)
        activeTabId = tab.id
        broadcast()
        await scheduleSave()
    }

    /// Moves focus to the tab identified by `id`. No-op if `id` is not present.
    public func focusTab(_ id: TabId) async {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        broadcast()
    }

    /// Removes the tab identified by `id`, cancels its watcher task, and
    /// advances focus to an adjacent tab (preferring the tab to the left).
    public func closeTab(_ id: TabId) async {
        await cancelWatcher(for: id)
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if activeTabId == id {
            activeTabId = adjacentTabId(removedAt: idx)
        }
        broadcast()
        await scheduleSave()
    }

    /// Reorders tabs to match `newOrder`.
    ///
    /// Tabs whose `TabId` does not appear in `newOrder` are silently dropped.
    /// Extra ids in `newOrder` that are not in `tabs` are ignored.
    public func reorderTabs(_ newOrder: [TabId]) async {
        let lookup = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        tabs = newOrder.compactMap { lookup[$0] }
        broadcast()
        await scheduleSave()
    }

    // MARK: Watcher registry

    /// Registers a background `Task` associated with a tab.
    ///
    /// The task is cancelled automatically when `closeTab(_:)` is called for
    /// the same `tabId`. Useful for log-follow or watch-stream tasks that must
    /// stop when the user closes the corresponding tab.
    public func registerWatcher(for tabId: TabId, task: Task<Void, Never>) async {
        watcherTasks[tabId]?.cancel()
        watcherTasks[tabId] = task
    }

    /// Cancels and removes the watcher task for `tabId`.
    public func cancelWatcher(for tabId: TabId) async {
        watcherTasks[tabId]?.cancel()
        watcherTasks.removeValue(forKey: tabId)
    }

    // MARK: Stream

    /// Returns an `AsyncStream` that emits the current snapshot immediately and
    /// on every subsequent mutation.
    ///
    /// The stream never finishes unless the actor is deallocated — callers must
    /// `break` or cancel the owning `Task` when the subscription is no longer needed.
    public func stateStream() -> AsyncStream<OpenTabsSnapshot> {
        let key = UUID()
        return AsyncStream { continuation in
            Task {
                await self.registerContinuation(continuation, key: key)
            }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: Persistence

    /// Loads the saved tab state from `persistenceURL` and replaces the current
    /// in-memory state. Call once on launch before the first `stateStream()` subscriber.
    ///
    /// - Throws: `CocoaError` / `DecodingError` on I/O or format failures.
    public func loadFromDisk() async throws {
        let data = try Data(contentsOf: persistenceURL)
        let payload = try JSONDecoder().decode(PersistedPayload.self, from: data)
        tabs = payload.tabs
        activeTabId = payload.activeTabId
        broadcast()
    }

    /// Schedules an atomic disk write debounced to 500 ms (ADR-0050).
    ///
    /// Each call cancels any pending write and re-arms the timer. The write uses
    /// a tmp file + `FileManager.replaceItemAt(_:withItemAt:)` for atomicity.
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
        _ continuation: AsyncStream<OpenTabsSnapshot>.Continuation,
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

    private var currentSnapshot: OpenTabsSnapshot {
        OpenTabsSnapshot(tabs: tabs, activeTabId: activeTabId)
    }

    private func adjacentTabId(removedAt idx: Int) -> TabId? {
        guard !tabs.isEmpty else { return nil }
        let candidateIdx = idx > 0 ? idx - 1 : 0
        return tabs[min(candidateIdx, tabs.count - 1)].id
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
            // Persistence failures are non-fatal — tabs remain open in memory.
        }
    }
}

// MARK: - PersistedPayload

/// Codable envelope stored in `open-tabs.json`.
private struct PersistedPayload: Codable, Sendable {
    let tabs: [DocumentTab]
    let activeTabId: TabId?
}
