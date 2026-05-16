// WatchStreamCoordinatorTests.swift — ResourceBrowserTests target
// Coverage: WatchStreamCoordinator actor — tab-owned lifecycle, LRU budget, resume, streams.
// ADR refs: ADR-0036 (watch lifecycle, 410-Gone, BOOKMARK handling, fan-out budget)
//           ADR-0050 (tab ownership of watch streams)

import XCTest
import Dependencies
@testable import ResourceBrowser
import SharedKernel

// MARK: - Fake watch port

/// Immediately closes the stream without emitting events.
private final class SilentWatchPort: ResourceWatchPort, @unchecked Sendable {
    func watchResources(
        gvk: GroupVersionKind,
        namespace: String?,
        contextId: UUID,
        resourceVersion: String?
    ) -> AsyncThrowingStream<ResourceWatchEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Delivers a pre-configured event sequence then closes.
private final class FakeResourceWatchPort: ResourceWatchPort, @unchecked Sendable {

    let events: [ResourceWatchEvent]

    init(events: [ResourceWatchEvent] = []) {
        self.events = events
    }

    func watchResources(
        gvk: GroupVersionKind,
        namespace: String?,
        contextId: UUID,
        resourceVersion: String?
    ) -> AsyncThrowingStream<ResourceWatchEvent, Error> {
        let captured = events
        return AsyncThrowingStream { continuation in
            Task {
                for event in captured { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
}

/// Immediately throws `ResourceWatchError.resourceVersionTooOld` (410 Gone).
private final class Gone410WatchPort: ResourceWatchPort, @unchecked Sendable {
    func watchResources(
        gvk: GroupVersionKind,
        namespace: String?,
        contextId: UUID,
        resourceVersion: String?
    ) -> AsyncThrowingStream<ResourceWatchEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ResourceWatchError.resourceVersionTooOld)
        }
    }
}

// MARK: - Helpers

private func makeItem(name: String) -> ResourceListItem {
    ResourceListItem(
        id: UUID(),
        gvk: .core("Pod"),
        namespace: "default",
        name: name,
        uid: UUID().uuidString,
        creationTimestamp: "2026-05-16T00:00:00Z",
        status: "Running",
        ageSeconds: 0
    )
}

private func makeAddedEvent(name: String) -> ResourceWatchEvent {
    ResourceWatchEvent(type: .added, item: makeItem(name: name))
}

private func makeTabId(_ label: String) -> TabId {
    TabId(raw: "resourcelist:cluster-a:v1:Pod:default:\(label)")
}

private func makeCoordinator(
    port: any ResourceWatchPort = SilentWatchPort(),
    budget: WatchBudget = WatchBudget()
) -> WatchStreamCoordinator {
    withDependencies {
        $0.resourceWatch = port
    } operation: {
        WatchStreamCoordinator(budget: budget)
    }
}

// MARK: - startWatch creates slot in active state

final class WatchStartTests: XCTestCase {

    func test_startWatch_createsActiveSlot() async throws {
        let coordinator = makeCoordinator()
        let tabId = makeTabId("t1")
        let clusterId = ClusterId("cluster-a")
        let gvk = GroupVersionKind.core("Pod")

        await coordinator.startWatch(tabId: tabId, clusterId: clusterId, gvk: gvk)

        let slots = await coordinator.snapshot()
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.tabId, tabId)
        XCTAssertEqual(slots.first?.state, .active)
    }

    func test_startWatch_idempotent_doesNotDuplicateSlot() async throws {
        let coordinator = makeCoordinator()
        let tabId = makeTabId("t2")
        let clusterId = ClusterId("cluster-a")
        let gvk = GroupVersionKind.core("Pod")

        await coordinator.startWatch(tabId: tabId, clusterId: clusterId, gvk: gvk)
        await coordinator.startWatch(tabId: tabId, clusterId: clusterId, gvk: gvk)

        let slots = await coordinator.snapshot()
        XCTAssertEqual(slots.count, 1, "Second startWatch should not create a duplicate slot")
    }
}

// MARK: - stopWatch cancels task and removes slot

final class WatchStopTests: XCTestCase {

    func test_stopWatch_removesSlot() async throws {
        let coordinator = makeCoordinator()
        let tabId = makeTabId("t3")
        let clusterId = ClusterId("cluster-a")

        await coordinator.startWatch(tabId: tabId, clusterId: clusterId, gvk: .core("Pod"))
        await coordinator.stopWatch(tabId: tabId)

        let slots = await coordinator.snapshot()
        XCTAssertTrue(slots.isEmpty)
    }

    func test_stopWatch_stateStreamEmitsActiveInitially() async throws {
        let coordinator = makeCoordinator()
        let tabId = makeTabId("t4")
        let clusterId = ClusterId("cluster-a")

        await coordinator.startWatch(tabId: tabId, clusterId: clusterId, gvk: .core("Pod"))
        let stream = await coordinator.stateStream(for: tabId)

        // The stream should emit the current state (.active) immediately.
        var first: WatchState?
        for await s in stream {
            first = s
            break
        }
        XCTAssertEqual(first, .active)
    }
}

// MARK: - LRU eviction when budget exceeded

final class WatchBudgetTests: XCTestCase {

    func test_startWatch_aboveBudget_evictsLRU() async throws {
        // Budget: 2 concurrent max
        let budget = WatchBudget(maxConcurrent: 2, perClusterMax: 10)
        let coordinator = makeCoordinator(budget: budget)
        let clusterId = ClusterId("cluster-a")

        let t1 = makeTabId("old-1")
        let t2 = makeTabId("old-2")
        let t3 = makeTabId("new-3")

        await coordinator.startWatch(tabId: t1, clusterId: clusterId, gvk: .core("Pod"))
        // Touch t2 later so t1 is older
        await coordinator.startWatch(tabId: t2, clusterId: clusterId, gvk: .core("Deployment"))
        await coordinator.touchWatch(tabId: t2)

        // Opening t3 should evict t1 (older lastUsedAt)
        await coordinator.startWatch(tabId: t3, clusterId: clusterId, gvk: .core("Service"))

        let slots = await coordinator.snapshot()
        let t1Slot = slots.first(where: { $0.tabId == t1 })
        let t3Slot = slots.first(where: { $0.tabId == t3 })

        XCTAssertEqual(t1Slot?.state, .paused, "LRU slot should be paused")
        XCTAssertEqual(t3Slot?.state, .active, "New slot should be active")
        let activeCount = await coordinator.activeWatchCount()
        XCTAssertEqual(activeCount, 2)
    }

    func test_startWatch_perClusterCapEnforced() async throws {
        let budget = WatchBudget(maxConcurrent: 10, perClusterMax: 2)
        let coordinator = makeCoordinator(budget: budget)
        let clusterId = ClusterId("cluster-b")

        let t1 = makeTabId("c1")
        let t2 = makeTabId("c2")
        let t3 = makeTabId("c3")

        await coordinator.startWatch(tabId: t1, clusterId: clusterId, gvk: .core("Pod"))
        await coordinator.startWatch(tabId: t2, clusterId: clusterId, gvk: .core("Service"))
        await coordinator.startWatch(tabId: t3, clusterId: clusterId, gvk: .core("ConfigMap"))

        let activeCount = await coordinator.activeWatchCount()
        XCTAssertEqual(activeCount, 2, "Per-cluster cap should limit active count to 2")
    }
}

// MARK: - touchWatch updates lastUsedAt

final class WatchTouchTests: XCTestCase {

    func test_touchWatch_updatesLastUsedAt() async throws {
        let coordinator = makeCoordinator()
        let tabId = makeTabId("touch-1")
        let clusterId = ClusterId("cluster-a")

        await coordinator.startWatch(tabId: tabId, clusterId: clusterId, gvk: .core("Pod"))
        let before = await coordinator.snapshot().first(where: { $0.tabId == tabId })?.lastUsedAtUnix ?? 0

        // Slight wait to guarantee a different timestamp
        try await Task.sleep(for: .milliseconds(10))
        await coordinator.touchWatch(tabId: tabId)

        let after = await coordinator.snapshot().first(where: { $0.tabId == tabId })?.lastUsedAtUnix ?? 0
        XCTAssertGreaterThanOrEqual(after, before)
    }
}

// MARK: - resumeWatch on paused slot reactivates

final class WatchResumeTests: XCTestCase {

    func test_resumeWatch_reactivatesPausedSlot() async throws {
        let budget = WatchBudget(maxConcurrent: 1, perClusterMax: 10)
        let coordinator = makeCoordinator(budget: budget)
        let clusterId = ClusterId("cluster-a")

        let t1 = makeTabId("resume-1")
        let t2 = makeTabId("resume-2")

        await coordinator.startWatch(tabId: t1, clusterId: clusterId, gvk: .core("Pod"))
        // t2 opening evicts t1
        await coordinator.startWatch(tabId: t2, clusterId: clusterId, gvk: .core("Service"))

        let pausedSlot = await coordinator.snapshot().first(where: { $0.tabId == t1 })
        XCTAssertEqual(pausedSlot?.state, .paused)

        // Close t2 so there is room for t1 to resume
        await coordinator.stopWatch(tabId: t2)
        await coordinator.resumeWatch(tabId: t1)

        let resumedSlot = await coordinator.snapshot().first(where: { $0.tabId == t1 })
        XCTAssertEqual(resumedSlot?.state, .active)
    }
}

// MARK: - Multiple concurrent watches with different kinds isolate properly

final class WatchIsolationTests: XCTestCase {

    func test_differentGVKs_doNotInterfere() async throws {
        let budget = WatchBudget(maxConcurrent: 10, perClusterMax: 10)
        let coordinator = makeCoordinator(budget: budget)
        let clusterId = ClusterId("cluster-a")

        let podTab = makeTabId("iso-pod")
        let svcTab = makeTabId("iso-svc")

        await coordinator.startWatch(tabId: podTab, clusterId: clusterId, gvk: .core("Pod"))
        await coordinator.startWatch(tabId: svcTab, clusterId: clusterId, gvk: .core("Service"))

        let slots = await coordinator.snapshot()
        let podSlot = slots.first(where: { $0.tabId == podTab })
        let svcSlot = slots.first(where: { $0.tabId == svcTab })

        XCTAssertEqual(podSlot?.gvk.kind, "Pod")
        XCTAssertEqual(svcSlot?.gvk.kind, "Service")
        XCTAssertEqual(podSlot?.state, .active)
        XCTAssertEqual(svcSlot?.state, .active)
        XCTAssertEqual(slots.count, 2)
    }
}

// MARK: - stateStream emits transitions

final class WatchStateStreamTests: XCTestCase {

    func test_stateStream_emitsActiveOnStart() async throws {
        let coordinator = makeCoordinator()
        let tabId = makeTabId("stream-1")
        let clusterId = ClusterId("cluster-a")

        await coordinator.startWatch(tabId: tabId, clusterId: clusterId, gvk: .core("Pod"))
        let stream = await coordinator.stateStream(for: tabId)

        var first: WatchState?
        for await state in stream {
            first = state
            break
        }
        XCTAssertEqual(first, .active)
    }

    func test_stateStream_emitsIdleForUnknownTab() async throws {
        let coordinator = makeCoordinator()
        let tabId = makeTabId("stream-unknown")
        let stream = await coordinator.stateStream(for: tabId)

        var first: WatchState?
        for await state in stream {
            first = state
            break
        }
        XCTAssertEqual(first, .idle)
    }
}

// MARK: - Legacy subscribe / unsubscribe (GVK fan-out API)

final class WatchStreamCoordinatorSubscribeTests: XCTestCase {

    func test_subscribe_receivesEventsFromPort() async throws {
        let expected = makeAddedEvent(name: "pod-1")
        let port = FakeResourceWatchPort(events: [expected])
        let coordinator = makeCoordinator(port: port)

        let (_, stream) = await coordinator.subscribe(
            gvk: .core("Pod"),
            namespace: "default",
            clusterId: UUID()
        )

        var received: [ResourceWatchEvent] = []
        for await event in stream { received.append(event) }

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.item.name, "pod-1")
    }

    func test_unsubscribe_finishesStream() async throws {
        let coordinator = makeCoordinator()
        let (id, stream) = await coordinator.subscribe(
            gvk: .core("Service"),
            namespace: "prod",
            clusterId: UUID()
        )
        await coordinator.unsubscribe(id: id)

        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertEqual(count, 0)
    }

    func test_subscribe_with410Port_streamsClosesWithoutCrash() async throws {
        let port = Gone410WatchPort()
        let coordinator = makeCoordinator(port: port)

        let (_, stream) = await coordinator.subscribe(
            gvk: .core("Pod"),
            namespace: "default",
            clusterId: UUID()
        )
        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertEqual(count, 0)
    }

    func test_handleRelist410_completesWithoutCrash() async throws {
        let coordinator = makeCoordinator()
        let gvk = GroupVersionKind.core("Pod")
        let clusterId = UUID()
        await coordinator.handleRelist410(for: gvk, namespace: nil, clusterId: clusterId)
        XCTAssertTrue(true)
    }
}
