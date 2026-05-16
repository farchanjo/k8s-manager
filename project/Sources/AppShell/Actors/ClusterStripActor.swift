// Actors/ClusterStripActor.swift — app_shell bounded context
// DDD role: AggregateRoot orchestration (actor)
// ADR ref: ADR-0051 (cluster strip state ownership and persistence)
// Persistence: ~/Library/Application Support/K8sManager/workspace/cluster-strip-pins.json
//
// Concurrency contract:
//   - All mutations are isolated to this actor.
//   - Save is debounced 500 ms per ADR-0051; a new mutation within the window
//     cancels the pending write and schedules a fresh one.
//   - Atomic write: write to a .tmp file then rename, preventing torn reads.

import Foundation
import Logging
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.cluster_strip_actor")

// MARK: - ClusterStripSnapshot

/// Sendable snapshot emitted by ``ClusterStripActor/stateStream()``.
public struct ClusterStripSnapshot: Sendable, Equatable {
    /// Ordered list of pinned clusters (ascending by `order`).
    public let pins: [ClusterStripPin]
    /// The currently selected cluster, or `nil` when the strip is empty.
    public let activeClusterId: ClusterId?

    public init(pins: [ClusterStripPin], activeClusterId: ClusterId?) {
        self.pins = pins
        self.activeClusterId = activeClusterId
    }
}

// MARK: - ClusterStripError

/// Typed errors thrown by ``ClusterStripActor``.
public enum ClusterStripError: Error, Sendable {
    /// Attempted to pin a 17th cluster when 16 are already pinned.
    case maxPinsReached
}

// MARK: - ClusterStripActor

/// Actor that owns the ordered list of pinned cluster sessions shown in the
/// vertical cluster strip (ADR-0051).
///
/// Consumers observe state via ``stateStream()`` — an `AsyncStream` that yields
/// a ``ClusterStripSnapshot`` on every mutation. The actor persists its state to
/// `~/Library/Application Support/K8sManager/workspace/cluster-strip-pins.json`
/// using an atomic write (write-to-tmp, then rename) debounced at 500 ms.
public actor ClusterStripActor {

    // MARK: Constants

    static let maxPins = 16
    private static let debounceNanoseconds: UInt64 = 500_000_000  // 500 ms

    // MARK: State

    /// Ordered list of pinned clusters (ascending by `order`).
    public private(set) var pins: [ClusterStripPin] = []

    /// The currently active (selected) cluster identifier.
    public private(set) var activeClusterId: ClusterId?

    // MARK: Internal

    private var continuations: [UUID: AsyncStream<ClusterStripSnapshot>.Continuation] = [:]
    private var persistTask: Task<Void, Never>?
    private let persistenceURL: URL

    // MARK: Init

    /// Creates the actor with the given persistence URL.
    ///
    /// - Parameter persistenceURL: Destination JSON file. Defaults to
    ///   `ApplicationPaths.supportDirectory/workspace/cluster-strip-pins.json`.
    public init(persistenceURL: URL = ClusterStripActor.defaultPersistenceURL) {
        self.persistenceURL = persistenceURL
    }

    /// Default persistence path per ADR-0026 addendum.
    public static var defaultPersistenceURL: URL {
        ApplicationPaths.supportDirectory
            .appendingPathComponent("workspace", isDirectory: true)
            .appendingPathComponent("cluster-strip-pins.json")
    }

    // MARK: Mutations

    /// Pins a cluster to the strip.
    ///
    /// Idempotent — if `clusterId` is already present, the call is a no-op.
    /// Throws ``ClusterStripError/maxPinsReached`` when 16 pins are already present.
    public func pin(clusterId: ClusterId, displayName: String) async throws {
        guard !pins.contains(where: { $0.clusterId == clusterId }) else { return }
        guard pins.count < Self.maxPins else { throw ClusterStripError.maxPinsReached }
        let now = ISO8601DateFormatter().string(from: Date())
        let pin = ClusterStripPin.make(
            clusterId: clusterId,
            displayName: displayName,
            pinnedAtRFC3339: now,
            order: pins.count
        )
        pins.append(pin)
        if activeClusterId == nil { activeClusterId = clusterId }
        broadcast()
        await scheduleSave()
    }

    /// Removes a cluster from the strip and renormalises order indices.
    public func unpin(_ clusterId: ClusterId) async {
        pins.removeAll { $0.clusterId == clusterId }
        normaliseOrder()
        if activeClusterId == clusterId {
            activeClusterId = pins.first?.clusterId
        }
        broadcast()
        await scheduleSave()
    }

    /// Marks `clusterId` as the active cluster for the sidebar tree.
    public func setActive(_ clusterId: ClusterId) async {
        guard pins.contains(where: { $0.clusterId == clusterId }) else { return }
        activeClusterId = clusterId
        broadcast()
    }

    /// Reorders pins to match `newOrder` (array of `ClusterId` in desired top-to-bottom order).
    ///
    /// ClusterIds not present in the current pin list are ignored.
    public func reorder(_ newOrder: [ClusterId]) async {
        var reordered: [ClusterStripPin] = []
        for (index, cid) in newOrder.enumerated() {
            guard let existing = pins.first(where: { $0.clusterId == cid }) else { continue }
            let updated = ClusterStripPin(
                clusterId: existing.clusterId,
                displayName: existing.displayName,
                initials: existing.initials,
                colorHex: existing.colorHex,
                pinnedAtRFC3339: existing.pinnedAtRFC3339,
                order: index
            )
            reordered.append(updated)
        }
        pins = reordered
        broadcast()
        await scheduleSave()
    }

    // MARK: Stream

    /// Returns an `AsyncStream` that emits a ``ClusterStripSnapshot`` on every
    /// mutation and once immediately with the current state.
    ///
    /// Marked `nonisolated` so callers (e.g. `@MainActor` view models) can
    /// open the stream without hopping to the actor's executor first. The
    /// continuation registration is dispatched asynchronously inside a `Task`.
    public nonisolated func stateStream() -> AsyncStream<ClusterStripSnapshot> {
        let key = UUID()
        return AsyncStream { continuation in
            Task {
                await self.addContinuation(continuation, key: key)
            }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: Persistence

    /// Loads state from disk. Call once at app launch before other mutations.
    public func loadFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        let data = try Data(contentsOf: persistenceURL)
        let state = try JSONDecoder().decode(PersistedState.self, from: data)
        pins = state.pins.sorted { $0.order < $1.order }
        activeClusterId = state.activeClusterId.map(ClusterId.init)
        log.info("ClusterStripActor loaded \(pins.count) pins from disk")
    }

    /// Schedules a debounced save. A new call within 500 ms cancels the pending write.
    private func scheduleSave() async {
        persistTask?.cancel()
        persistTask = Task {
            do { try await Task.sleep(nanoseconds: Self.debounceNanoseconds) } catch { return }
            await self.flushToDisk()
        }
    }

    private func flushToDisk() {
        let snapshot = PersistedState(
            pins: pins,
            activeClusterId: activeClusterId?.rawValue,
            lastPersistedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try ensureParentDirectory()
            let tmpURL = persistenceURL.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: tmpURL, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(persistenceURL, withItemAt: tmpURL)
            log.debug("ClusterStripActor persisted \(pins.count) pins")
        } catch {
            log.error("ClusterStripActor persist failed: \(error)")
        }
    }

    // MARK: Private helpers

    private func ensureParentDirectory() throws {
        let dir = persistenceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func normaliseOrder() {
        pins = pins.enumerated().map { index, pin in
            ClusterStripPin(
                clusterId: pin.clusterId,
                displayName: pin.displayName,
                initials: pin.initials,
                colorHex: pin.colorHex,
                pinnedAtRFC3339: pin.pinnedAtRFC3339,
                order: index
            )
        }
    }

    private func addContinuation(
        _ continuation: AsyncStream<ClusterStripSnapshot>.Continuation,
        key: UUID
    ) {
        continuation.yield(currentSnapshot)
        continuations[key] = continuation
    }

    private func removeContinuation(key: UUID) {
        continuations.removeValue(forKey: key)
    }

    private func broadcast() {
        let snap = currentSnapshot
        for cont in continuations.values { cont.yield(snap) }
    }

    private var currentSnapshot: ClusterStripSnapshot {
        ClusterStripSnapshot(pins: pins, activeClusterId: activeClusterId)
    }
}

// MARK: - PersistedState

/// JSON envelope written to `cluster-strip-pins.json`.
private struct PersistedState: Codable, Sendable {
    let pins: [ClusterStripPin]
    let activeClusterId: String?
    let lastPersistedAt: String
}
