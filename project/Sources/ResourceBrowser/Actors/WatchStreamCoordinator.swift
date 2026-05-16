// Actors/WatchStreamCoordinator.swift — resource_browser bounded context
// DDD role: DomainService (actor) — tab-owned watch lifecycle + LRU budget
// ADR refs: ADR-0036 (watch stream lifecycle, 410-Gone, fan-out budget, LRU eviction)
//           ADR-0050 (tab ownership of watch streams)

import Dependencies
import Foundation
import Logging
import SharedKernel

// MARK: - WatchBudget

/// Concurrent watch stream limits enforced by `WatchStreamCoordinator`.
public struct WatchBudget: Sendable {
    /// Maximum active watches across all clusters.
    public let maxConcurrent: Int
    /// Maximum active watches per individual cluster.
    public let perClusterMax: Int

    /// Default limits informed by ADR-0036 §Fan-out budget.
    public init(maxConcurrent: Int = 10, perClusterMax: Int = 5) {
        self.maxConcurrent = maxConcurrent
        self.perClusterMax = perClusterMax
    }
}

// MARK: - WatchState

/// Observable lifecycle state of a single tab's watch stream.
public enum WatchState: Sendable, Equatable {
    /// No watch is running for this tab.
    case idle
    /// Watch stream is open and receiving events.
    case active
    /// Watch was evicted by LRU policy; operator must resume manually.
    case paused
    /// Watch encountered an unrecoverable error.
    case errored(String)
}

// MARK: - WatchSlot

/// Snapshot of a single tab's watch registration.
public struct WatchSlot: Sendable {
    /// The tab that owns this watch (shared-kernel type).
    public let tabId: TabId
    /// The cluster being watched.
    public let clusterId: ClusterId
    /// The Kubernetes GVK being watched.
    public let gvk: GroupVersionKind
    /// Unix timestamp of the last activity (used for LRU ordering).
    public let lastUsedAtUnix: Double
    /// Current lifecycle state.
    public var state: WatchState

    /// Returns a copy with an updated `lastUsedAtUnix`.
    func touched(at unix: Double) -> WatchSlot {
        WatchSlot(
            tabId: tabId,
            clusterId: clusterId,
            gvk: gvk,
            lastUsedAtUnix: unix,
            state: state
        )
    }

    /// Returns a copy with a new `WatchState`.
    func withState(_ newState: WatchState) -> WatchSlot {
        WatchSlot(
            tabId: tabId,
            clusterId: clusterId,
            gvk: gvk,
            lastUsedAtUnix: lastUsedAtUnix,
            state: newState
        )
    }
}

// MARK: - WatchStreamCoordinator

/// Actor that owns tab-level watch stream lifecycle with LRU budget enforcement.
///
/// Each open tab that requires live data (resourceList, resourceDetail, etc.)
/// calls `startWatch(tabId:clusterId:gvk:)`. The coordinator:
///
/// - Maps each `TabId` to one active `WatchSlot` + draining `Task`.
/// - Enforces `WatchBudget` by evicting the least-recently-used slot when
///   `maxConcurrent` or `perClusterMax` is reached (ADR-0036 §Fan-out budget).
/// - Broadcasts `WatchState` transitions through per-tab `AsyncStream`.
/// - Also exposes the legacy GVK-keyed fan-out `subscribe`/`unsubscribe` API.
///
/// One coordinator instance should be registered as a singleton dependency
/// and wired at the composition root (ADR-0020).
public actor WatchStreamCoordinator {

    // MARK: - Dependencies

    @Dependency(\.resourceWatch) private var watchPort

    // MARK: - Tab-slot state

    private var slots: [TabId: WatchSlot] = [:]
    private var tasks: [TabId: Task<Void, Never>] = [:]
    private var stateConts: [TabId: [UUID: AsyncStream<WatchState>.Continuation]] = [:]

    // MARK: - Legacy GVK fan-out state

    private struct LegacyKey: Hashable, Sendable {
        let clusterId: UUID
        let gvk: GroupVersionKind
        let namespace: String?
    }

    private struct LegacyEntry: Sendable {
        let task: Task<Void, Never>
        let continuations: [UUID: AsyncStream<ResourceWatchEvent>.Continuation]
    }

    private var legacyStreams: [LegacyKey: LegacyEntry] = [:]
    private var lastKnownRV: [LegacyKey: String] = [:]

    // MARK: - Config

    private let budget: WatchBudget
    private let logger: Logger

    // MARK: - Init

    /// Creates a coordinator with the given budget and logger.
    public init(
        budget: WatchBudget = WatchBudget(),
        logger: Logger = Logger(label: "resource_browser.watch_coordinator")
    ) {
        self.budget = budget
        self.logger = logger
    }

    // MARK: - Tab-owned API

    /// Starts a watch for `tabId`. Evicts LRU slots when budget is exceeded.
    ///
    /// Idempotent: calling again for an already-active tab bumps `lastUsedAt`.
    public func startWatch(
        tabId: TabId,
        clusterId: ClusterId,
        gvk: GroupVersionKind
    ) async {
        if slots[tabId] != nil {
            await touchWatch(tabId: tabId)
            return
        }
        await enforceBudget(clusterId: clusterId)
        let slot = WatchSlot(
            tabId: tabId,
            clusterId: clusterId,
            gvk: gvk,
            lastUsedAtUnix: Date().timeIntervalSince1970,
            state: .active
        )
        slots[tabId] = slot
        spawnTask(for: tabId, clusterId: clusterId, gvk: gvk)
        broadcastState(.active, for: tabId)
        logger.debug("Watch started tabId=\(tabId.raw) gvk=\(gvk.kind)")
    }

    /// Cancels the watch for `tabId` and removes its slot.
    public func stopWatch(tabId: TabId) async {
        tasks[tabId]?.cancel()
        tasks.removeValue(forKey: tabId)
        slots.removeValue(forKey: tabId)
        broadcastState(.idle, for: tabId)
        finishStateConts(for: tabId)
        logger.debug("Watch stopped tabId=\(tabId.raw)")
    }

    /// Bumps `lastUsedAt` for LRU ordering without changing state.
    public func touchWatch(tabId: TabId) async {
        guard let existing = slots[tabId] else { return }
        slots[tabId] = existing.touched(at: Date().timeIntervalSince1970)
    }

    /// Evicts the globally least-recently-used active slot to `.paused`.
    public func pauseLRU() async {
        guard let lruId = lruTabId() else { return }
        await pauseSlot(tabId: lruId)
    }

    /// Re-activates a paused watch. May evict another LRU slot to make room.
    public func resumeWatch(tabId: TabId) async {
        guard var slot = slots[tabId], slot.state == .paused else { return }
        let clusterId = slot.clusterId
        let gvk = slot.gvk
        await enforceBudget(clusterId: clusterId)
        slot = slot.withState(.active).touched(at: Date().timeIntervalSince1970)
        slots[tabId] = slot
        spawnTask(for: tabId, clusterId: clusterId, gvk: gvk)
        broadcastState(.active, for: tabId)
        logger.debug("Watch resumed tabId=\(tabId.raw)")
    }

    /// Returns an immutable snapshot of all current slots.
    public func snapshot() async -> [WatchSlot] {
        Array(slots.values)
    }

    /// Returns an `AsyncStream` emitting `WatchState` transitions for `tabId`.
    ///
    /// Emits the current state immediately, then on each subsequent transition.
    public func stateStream(for tabId: TabId) -> AsyncStream<WatchState> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.registerStateCont(continuation, key: key, tabId: tabId) }
            continuation.onTermination = { _ in
                Task { await self.removeStateCont(key: key, tabId: tabId) }
            }
        }
    }

    /// Count of slots in `.active` state. Consumed by `StatusBarView`.
    public func activeWatchCount() async -> Int {
        slots.values.filter { $0.state == .active }.count
    }

    // MARK: - Legacy GVK fan-out API

    /// Opens or reuses a watch stream for the given GVK / namespace / cluster key.
    ///
    /// Multiple callers for the same key share one underlying watch stream.
    /// Returns a subscription `id` and an `AsyncStream<ResourceWatchEvent>`.
    public func subscribe(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: UUID
    ) -> (id: UUID, stream: AsyncStream<ResourceWatchEvent>) {
        let key = LegacyKey(clusterId: clusterId, gvk: gvk, namespace: namespace)
        let subId = UUID()
        var cont: AsyncStream<ResourceWatchEvent>.Continuation?
        let stream = AsyncStream<ResourceWatchEvent> { c in cont = c }
        guard let continuation = cont else {
            preconditionFailure("AsyncStream continuation unavailable")
        }
        if var entry = legacyStreams[key] {
            var conts = entry.continuations
            conts[subId] = continuation
            legacyStreams[key] = LegacyEntry(task: entry.task, continuations: conts)
        } else {
            let task = Task<Void, Never> { [weak self] in
                if let self { await self.drainLegacy(key: key) }
            }
            legacyStreams[key] = LegacyEntry(
                task: task,
                continuations: [subId: continuation]
            )
        }
        return (subId, stream)
    }

    /// Removes a subscriber. Cancels the drain task when the last subscriber leaves.
    public func unsubscribe(id: UUID) {
        for key in legacyStreams.keys {
            guard let entry = legacyStreams[key],
                  let cont = entry.continuations[id] else { continue }
            cont.finish()
            var conts = entry.continuations
            conts.removeValue(forKey: id)
            if conts.isEmpty {
                entry.task.cancel()
                legacyStreams.removeValue(forKey: key)
                lastKnownRV.removeValue(forKey: key)
                logger.debug("Cancelled watch gvk=\(key.gvk.kind)")
            } else {
                legacyStreams[key] = LegacyEntry(task: entry.task, continuations: conts)
            }
            return
        }
    }

    /// Clears a stale resource version for 410-Gone recovery (ADR-0036 §Phase 4).
    public func handleRelist410(
        for gvk: GroupVersionKind,
        namespace: String?,
        clusterId: UUID
    ) {
        let key = LegacyKey(clusterId: clusterId, gvk: gvk, namespace: namespace)
        lastKnownRV.removeValue(forKey: key)
        logger.info("410 Gone — cleared RV for gvk=\(gvk.kind), will relist")
    }

    // MARK: - Private: tab task lifecycle

    private func spawnTask(
        for tabId: TabId,
        clusterId: ClusterId,
        gvk: GroupVersionKind
    ) {
        tasks[tabId]?.cancel()
        let task = Task<Void, Never> { [weak self] in
            if let self { await self.drainTab(tabId: tabId, clusterId: clusterId, gvk: gvk) }
        }
        tasks[tabId] = task
    }

    private func drainTab(
        tabId: TabId,
        clusterId: ClusterId,
        gvk: GroupVersionKind
    ) async {
        let contextId = UUID(uuidString: clusterId.rawValue) ?? UUID()
        let stream = watchPort.watchResources(
            gvk: gvk,
            namespace: nil,
            contextId: contextId,
            resourceVersion: nil
        )
        do {
            for try await _ in stream {
                guard !Task.isCancelled else { break }
            }
        } catch {
            guard !Task.isCancelled else { return }
            let reason = String(describing: error)
            transitionState(.errored(reason), for: tabId)
            logger.warning("Watch error tabId=\(tabId.raw): \(reason)")
        }
    }

    // MARK: - Private: legacy drain

    private func drainLegacy(key: LegacyKey) async {
        let rv = lastKnownRV[key]
        let stream = watchPort.watchResources(
            gvk: key.gvk,
            namespace: key.namespace,
            contextId: key.clusterId,
            resourceVersion: rv
        )
        do {
            for try await event in stream {
                if event.type == .bookmark {
                    lastKnownRV[key] = event.item.uid
                    continue
                }
                fanOut(event: event, key: key)
            }
        } catch ResourceWatchError.resourceVersionTooOld {
            handleRelist410(
                for: key.gvk,
                namespace: key.namespace,
                clusterId: key.clusterId
            )
        } catch {
            logger.warning("Watch stream error gvk=\(key.gvk.kind): \(error)")
        }
        // When the port stream closes, finish all subscriber continuations.
        finishLegacy(key: key)
    }

    private func fanOut(event: ResourceWatchEvent, key: LegacyKey) {
        guard let entry = legacyStreams[key] else { return }
        for cont in entry.continuations.values { cont.yield(event) }
    }

    private func finishLegacy(key: LegacyKey) {
        guard let entry = legacyStreams[key] else { return }
        entry.continuations.values.forEach { $0.finish() }
        legacyStreams.removeValue(forKey: key)
    }

    // MARK: - Private: budget enforcement

    private func enforceBudget(clusterId: ClusterId) async {
        while activeCountSync() >= budget.maxConcurrent {
            guard let lru = lruTabId() else { break }
            await pauseSlot(tabId: lru)
        }
        while clusterActiveCount(clusterId: clusterId) >= budget.perClusterMax {
            guard let lru = lruTabId(clusterId: clusterId) else { break }
            await pauseSlot(tabId: lru)
        }
    }

    private func pauseSlot(tabId: TabId) async {
        tasks[tabId]?.cancel()
        tasks.removeValue(forKey: tabId)
        guard let existing = slots[tabId] else { return }
        slots[tabId] = existing.withState(.paused)
        broadcastState(.paused, for: tabId)
        logger.info("Watch LRU evicted tabId=\(tabId.raw)")
    }

    private func activeCountSync() -> Int {
        slots.values.filter { $0.state == .active }.count
    }

    private func clusterActiveCount(clusterId: ClusterId) -> Int {
        slots.values.filter {
            $0.clusterId == clusterId && $0.state == .active
        }.count
    }

    private func lruTabId(clusterId: ClusterId? = nil) -> TabId? {
        slots.values
            .filter {
                $0.state == .active
                && (clusterId == nil || $0.clusterId == clusterId)
            }
            .min(by: { $0.lastUsedAtUnix < $1.lastUsedAtUnix })
            .map(\.tabId)
    }

    // MARK: - Private: state broadcast

    private func transitionState(_ state: WatchState, for tabId: TabId) {
        guard var slot = slots[tabId] else { return }
        slot = slot.withState(state)
        slots[tabId] = slot
        broadcastState(state, for: tabId)
    }

    private func broadcastState(_ state: WatchState, for tabId: TabId) {
        guard let conts = stateConts[tabId] else { return }
        for cont in conts.values { cont.yield(state) }
    }

    private func finishStateConts(for tabId: TabId) {
        stateConts[tabId]?.values.forEach { $0.finish() }
        stateConts.removeValue(forKey: tabId)
    }

    private func registerStateCont(
        _ continuation: AsyncStream<WatchState>.Continuation,
        key: UUID,
        tabId: TabId
    ) {
        let current = slots[tabId]?.state ?? .idle
        continuation.yield(current)
        var existing = stateConts[tabId] ?? [:]
        existing[key] = continuation
        stateConts[tabId] = existing
    }

    private func removeStateCont(key: UUID, tabId: TabId) {
        stateConts[tabId]?[key] = nil
        if stateConts[tabId]?.isEmpty == true {
            stateConts.removeValue(forKey: tabId)
        }
    }
}
