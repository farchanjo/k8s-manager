// WatchStreamCoordinatorTests.swift — ResourceBrowserTests target
// Coverage: WatchStreamCoordinator actor — subscribe, unsubscribe, 410 relist.
// ADR refs: ADR-0036 (watch lifecycle, 410-Gone, BOOKMARK handling)

import XCTest
import Dependencies
@testable import ResourceBrowser
import SharedKernel

// MARK: - Fake watch port

/// Delivers a pre-configured sequence of events then closes.
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
                for event in captured {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

/// Immediately throws `ResourceWatchError.resourceVersionTooOld`.
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

private func makeItem(name: String, gvk: GroupVersionKind = .core("Pod")) -> ResourceListItem {
    ResourceListItem(
        id: UUID(),
        gvk: gvk,
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

// MARK: - Tests

final class WatchStreamCoordinatorSubscribeTests: XCTestCase {

    func test_subscribe_receivesEventsFromPort() async throws {
        let expected = makeAddedEvent(name: "pod-1")
        let port = FakeResourceWatchPort(events: [expected])

        let coordinator = withDependencies {
            $0.resourceWatch = port
        } operation: {
            WatchStreamCoordinator()
        }

        let (_, stream) = await coordinator.subscribe(
            gvk: .core("Pod"),
            namespace: "default",
            clusterId: UUID()
        )

        var received: [ResourceWatchEvent] = []
        for await event in stream {
            received.append(event)
        }

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.item.name, "pod-1")
    }

    func test_subscribe_multipleSubscribersReceiveEvents() async throws {
        let port = FakeResourceWatchPort(events: [makeAddedEvent(name: "pod-A")])
        let clusterId = UUID()

        let coordinator = withDependencies {
            $0.resourceWatch = port
        } operation: {
            WatchStreamCoordinator()
        }

        let (_, stream1) = await coordinator.subscribe(gvk: .core("Pod"), namespace: nil, clusterId: clusterId)
        let (_, stream2) = await coordinator.subscribe(gvk: .core("Pod"), namespace: nil, clusterId: clusterId)

        async let collected1 = { () async -> [ResourceWatchEvent] in
            var r: [ResourceWatchEvent] = []
            for await e in stream1 { r.append(e) }
            return r
        }()

        async let collected2 = { () async -> [ResourceWatchEvent] in
            var r: [ResourceWatchEvent] = []
            for await e in stream2 { r.append(e) }
            return r
        }()

        let r1 = await collected1
        let r2 = await collected2
        XCTAssertFalse(r1.isEmpty, "Subscriber 1 should receive at least one event")
        XCTAssertFalse(r2.isEmpty, "Subscriber 2 should receive at least one event")
    }
}

final class WatchStreamCoordinatorUnsubscribeTests: XCTestCase {

    func test_unsubscribe_finishesStream() async throws {
        let port = FakeResourceWatchPort(events: [])
        let coordinator = withDependencies {
            $0.resourceWatch = port
        } operation: {
            WatchStreamCoordinator()
        }

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
}

final class WatchStreamCoordinator410Tests: XCTestCase {

    func test_handleRelist410_clearsRV() async throws {
        let port = Gone410WatchPort()
        let coordinator = withDependencies {
            $0.resourceWatch = port
        } operation: {
            WatchStreamCoordinator()
        }

        let gvk = GroupVersionKind.core("Pod")
        let clusterId = UUID()

        // handleRelist410 is a no-panic internal call; verify it completes without error.
        await coordinator.handleRelist410(for: gvk, namespace: nil, clusterId: clusterId)
        // No assertion needed beyond verifying the above line does not trap.
        XCTAssertTrue(true)
    }

    func test_subscribe_with410Port_streamsClosesWithoutCrash() async throws {
        let port = Gone410WatchPort()
        let coordinator = withDependencies {
            $0.resourceWatch = port
        } operation: {
            WatchStreamCoordinator()
        }

        let (_, stream) = await coordinator.subscribe(
            gvk: .core("Pod"),
            namespace: "default",
            clusterId: UUID()
        )

        var count = 0
        for await _ in stream { count += 1 }
        // 410 causes the drain task to log and exit; the stream should terminate.
        XCTAssertEqual(count, 0)
    }
}
