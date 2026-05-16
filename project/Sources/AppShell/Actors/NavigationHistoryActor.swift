// Actors/NavigationHistoryActor.swift — app_shell bounded context
// DDD role: Aggregate root — per-window navigation history
// ADR ref: ADR-0065 (Navigation history stack — back/forward within tab)

import Foundation
import SharedKernel

// MARK: - NavigationHistoryActor

/// Actor that owns the per-window navigation history deque.
///
/// Responsibilities (per ADR-0065):
/// - Maintains an ordered `[NavigationEntry]` deque with a cursor pointer.
/// - Capacity-bounded to 100 entries; oldest entry evicted on overflow.
/// - Exposes `push(_:)`, `back()`, `forward()`, and `clear()` commands.
/// - On `push`, truncates forward entries beyond the current cursor (browser semantics).
/// - Guards duplicate suppression: entry identical to cursor is not pushed.
/// - Guards restore suppression: `isRestoring == true` blocks push.
/// - Persists the deque up to the cursor on every mutation (debounced 500 ms).
/// - On cold launch, restores the most-recent 50 entries from disk.
/// - Broadcasts `NavigationHistorySnapshot` to all stream observers.
public actor NavigationHistoryActor {

    // MARK: Constants

    /// Maximum number of entries in the deque.
    public static let maxCapacity = 100
    /// Number of entries restored on cold launch.
    public static let coldLaunchRestoreLimit = 50

    // MARK: Private state

    /// Flat deque of recorded navigation entries.
    private var deque: [NavigationEntry] = []
    /// Zero-based index of the current position within `deque`.
    private var cursor: Int = -1
    /// When `true`, `push(_:)` is suppressed (restore or programmatic back/forward).
    private var isRestoring: Bool = false
    /// Live `AsyncStream` continuations for `stateStream()` subscribers.
    private var continuations: [UUID: AsyncStream<NavigationHistorySnapshot>.Continuation] = [:]
    /// Debounce task for the 500 ms persistence window.
    private var persistTask: Task<Void, Never>?
    /// Canonical persistence URL for the history JSON.
    private let persistenceURL: URL

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameter persistenceURL: JSON file location for history persistence.
    ///   Production callers should pass
    ///   `ApplicationPaths.workspaceStateRoot
    ///       .appendingPathComponent("navigation-history.json")`.
    public init(persistenceURL: URL) {
        self.persistenceURL = persistenceURL
    }

    // MARK: Public read accessors

    /// Current deque (back entries + forward entries as a flat array).
    public var entries: [NavigationEntry] { deque }

    /// Current cursor position (−1 when deque is empty).
    public var cursorIndex: Int { cursor }

    // MARK: Commands

    /// Pushes `entry` onto the history stack.
    ///
    /// Suppressed when:
    /// - `isRestoring == true`.
    /// - `entry` is a duplicate of the entry at the current cursor.
    ///
    /// On push:
    /// 1. Truncates any entries beyond `cursor` (discards stale forward chain).
    /// 2. Appends the new entry.
    /// 3. Advances `cursor` to the new tail.
    /// 4. Evicts the oldest entry if `deque.count > maxCapacity`.
    public func push(_ entry: NavigationEntry) async {
        guard !isRestoring else { return }
        if let current = currentEntry, current.isDuplicate(of: entry) { return }
        if cursor < deque.count - 1 {
            deque.removeSubrange((cursor + 1)...)
        }
        deque.append(entry)
        cursor = deque.count - 1
        if deque.count > Self.maxCapacity {
            deque.removeFirst()
            cursor = deque.count - 1
        }
        broadcast()
        await scheduleSave()
    }

    /// Moves the cursor one position toward the beginning.
    ///
    /// - Returns: The entry at the new cursor position, or `nil` when already
    ///   at the oldest entry.
    public func back() async -> NavigationEntry? {
        guard cursor > 0 else { return nil }
        cursor -= 1
        broadcast()
        return deque[cursor]
    }

    /// Moves the cursor one position toward the end.
    ///
    /// - Returns: The entry at the new cursor position, or `nil` when already
    ///   at the newest entry.
    public func forward() async -> NavigationEntry? {
        guard cursor < deque.count - 1 else { return nil }
        cursor += 1
        broadcast()
        return deque[cursor]
    }

    /// Clears the entire history deque and resets the cursor.
    ///
    /// Called when the relevant tab lifecycle requires a full history wipe
    /// (e.g., closing the last tab or an explicit clear request).
    public func clear() async {
        deque.removeAll()
        cursor = -1
        broadcast()
        await scheduleSave()
    }

    // MARK: Stream

    /// Returns an `AsyncStream` that emits the current snapshot immediately and
    /// on every subsequent mutation.
    public func stateStream() -> AsyncStream<NavigationHistorySnapshot> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.registerContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: Persistence

    /// Loads history from `persistenceURL` and replaces in-memory state.
    ///
    /// Restores at most ``coldLaunchRestoreLimit`` (50) entries and positions
    /// the cursor at the last restored entry. Guards `isRestoring` during
    /// the restoration so push calls from reactive observers are suppressed.
    public func loadFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        let data = try Data(contentsOf: persistenceURL)
        let payload = try JSONDecoder().decode(PersistedPayload.self, from: data)
        isRestoring = true
        defer { isRestoring = false }
        let limited = Array(payload.entries.suffix(Self.coldLaunchRestoreLimit))
        deque = limited
        cursor = limited.isEmpty ? -1 : limited.count - 1
        broadcast()
    }

    // MARK: Private helpers

    private var currentEntry: NavigationEntry? {
        guard cursor >= 0, cursor < deque.count else { return nil }
        return deque[cursor]
    }

    private func registerContinuation(
        _ continuation: AsyncStream<NavigationHistorySnapshot>.Continuation,
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

    private var currentSnapshot: NavigationHistorySnapshot {
        NavigationHistorySnapshot(
            canGoBack: cursor > 0,
            canGoForward: cursor < deque.count - 1,
            entryCount: deque.count,
            cursorIndex: cursor
        )
    }

    private func scheduleSave() async {
        persistTask?.cancel()
        // Persist entries up to and including cursor; discard forward chain.
        let entriesToSave = cursor >= 0 ? Array(deque[...cursor]) : []
        let snapshot = PersistedPayload(entries: entriesToSave)
        let url = persistenceURL
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Self.writeToDisk(payload: snapshot, url: url)
        }
    }

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
            // Persistence failures are non-fatal.
        }
    }
}

// MARK: - PersistedPayload

/// Codable envelope stored in `navigation-history.json`.
private struct PersistedPayload: Codable, Sendable {
    let entries: [NavigationEntry]
}
