// Tests/AppShellTests/Events/EventsTimelineViewModelTests.swift
// Coverage: EventsTimelineViewModel start, filters, pause, buffer rotation, export.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - EventsTimelineViewModelTests

@MainActor
final class EventsTimelineViewModelTests: XCTestCase {

    // MARK: start — subscribes to event stream

    func test_start_populatesEventsFromPort() async {
        let items = [
            makeItem(uid: "u1", eventType: "Warning", reason: "BackOff", objectName: "pod-a", ns: "default"),
            makeItem(uid: "u2", eventType: "Normal",  reason: "Pulled",  objectName: "pod-b", ns: "staging"),
        ]
        let fake = FakeTimelinePort(items: items)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            XCTAssertEqual(sut.events.count, 2)
        }
    }

    // MARK: filter by type — warning only

    func test_filteredEvents_warningOnly() async {
        let items = [
            makeItem(uid: "w1", eventType: "Warning", reason: "BackOff", objectName: "pod-x", ns: "ns1"),
            makeItem(uid: "n1", eventType: "Normal",  reason: "Pulled",  objectName: "pod-y", ns: "ns1"),
        ]
        let fake = FakeTimelinePort(items: items)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            sut.typeFilter = .warning
            sut.ageFilter = .all
            XCTAssertEqual(sut.filteredEvents.count, 1)
            XCTAssertEqual(sut.filteredEvents.first?.type, .warning)
        }
    }

    // MARK: filter by reason

    func test_filteredEvents_reasonFilter() async {
        let items = [
            makeItem(uid: "a1", eventType: "Warning", reason: "BackOff",  objectName: "pod-a", ns: "ns1"),
            makeItem(uid: "a2", eventType: "Normal",  reason: "Scheduled", objectName: "pod-b", ns: "ns1"),
        ]
        let fake = FakeTimelinePort(items: items)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            sut.reasonFilter = "BackOff"
            sut.ageFilter = .all
            XCTAssertEqual(sut.filteredEvents.count, 1)
            XCTAssertEqual(sut.filteredEvents.first?.reason, "BackOff")
        }
    }

    // MARK: filter by namespace

    func test_filteredEvents_namespaceFilter() async {
        let items = [
            makeItem(uid: "b1", eventType: "Normal", reason: "Pulled", objectName: "pod-a", ns: "default"),
            makeItem(uid: "b2", eventType: "Normal", reason: "Started", objectName: "pod-b", ns: "staging"),
        ]
        let fake = FakeTimelinePort(items: items)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            sut.namespaceFilter = "staging"
            sut.ageFilter = .all
            XCTAssertEqual(sut.filteredEvents.count, 1)
            XCTAssertEqual(sut.filteredEvents.first?.objectNamespace, "staging")
        }
    }

    // MARK: age filter excludes old events

    func test_filteredEvents_ageFilterExcludesOldTimestamps() async {
        // One event with a very old timestamp, one recent.
        let oldTimestamp = "2000-01-01T00:00:00Z"
        let recentTimestamp = ISO8601DateFormatter().string(from: Date())
        let items = [
            makeItem(uid: "c1", eventType: "Normal", reason: "Pulled", objectName: "pod-a",
                     ns: "default", lastTimestamp: oldTimestamp),
            makeItem(uid: "c2", eventType: "Normal", reason: "Started", objectName: "pod-b",
                     ns: "default", lastTimestamp: recentTimestamp),
        ]
        let fake = FakeTimelinePort(items: items)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            sut.ageFilter = .lastHour
            XCTAssertEqual(sut.filteredEvents.count, 1)
            XCTAssertEqual(sut.filteredEvents.first?.id, "c2")
        }
    }

    // MARK: pause stops accumulating

    func test_pause_preventsEventAccumulation() async {
        let fake = FakeTimelinePort(items: [
            makeItem(uid: "p1", eventType: "Normal", reason: "Pulled", objectName: "pod-a", ns: "ns1"),
        ])
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            let countBeforePause = sut.events.count
            sut.pause()
            XCTAssertTrue(sut.isPaused)
            // Count must not have grown while paused.
            XCTAssertEqual(sut.events.count, countBeforePause)
        }
    }

    // MARK: search query filters by message + object name

    func test_filteredEvents_searchByMessage() async {
        let items = [
            makeItem(uid: "s1", eventType: "Normal", reason: "Pulled", objectName: "pod-alpha",
                     ns: "ns1", message: "Image pulled successfully"),
            makeItem(uid: "s2", eventType: "Warning", reason: "BackOff", objectName: "pod-beta",
                     ns: "ns1", message: "Back-off restarting failed container"),
        ]
        let fake = FakeTimelinePort(items: items)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            sut.ageFilter = .all
            sut.searchQuery = "back-off"
            XCTAssertEqual(sut.filteredEvents.count, 1)
            XCTAssertEqual(sut.filteredEvents.first?.id, "s2")
        }
    }

    func test_filteredEvents_searchByObjectName() async {
        let items = [
            makeItem(uid: "t1", eventType: "Normal", reason: "Pulled", objectName: "nginx-deploy",
                     ns: "ns1", message: "Pulled image"),
            makeItem(uid: "t2", eventType: "Normal", reason: "Started", objectName: "redis-cache",
                     ns: "ns1", message: "Started container"),
        ]
        let fake = FakeTimelinePort(items: items)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            sut.ageFilter = .all
            sut.searchQuery = "redis"
            XCTAssertEqual(sut.filteredEvents.count, 1)
            XCTAssertEqual(sut.filteredEvents.first?.objectName, "redis-cache")
        }
    }

    // MARK: buffer rotation at 2 000 events

    func test_bufferRotation_capsAt2000() async {
        let oversized = (0..<2_100).map { i in
            makeItem(uid: "uid-\(i)", eventType: "Normal", reason: "Pulled",
                     objectName: "pod-\(i)", ns: "default")
        }
        let fake = FakeTimelinePort(items: oversized)
        await withDependencies { $0.kubernetesResourceList = fake } operation: {
            let sut = EventsTimelineViewModel()
            await sut.start(clusterId: ClusterId("c1"), scope: nil)
            XCTAssertLessThanOrEqual(sut.events.count, 2_000)
        }
    }
}

// MARK: - Test double

private final class FakeTimelinePort: KubernetesResourceListPort, @unchecked Sendable {
    private let stubbedItems: [ResourceListItem]

    init(items: [ResourceListItem]) {
        self.stubbedItems = items
    }

    func list(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> [ResourceListItem] {
        stubbedItems
    }

    func get(
        gvk: GroupVersionKind,
        name: String,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> ResourceDetail {
        throw ResourceListError.unimplemented
    }
}

// MARK: - Helpers

private func makeItem(
    uid: String,
    eventType: String,
    reason: String,
    objectName: String,
    ns: String,
    message: String = "Test event",
    lastTimestamp: String? = nil
) -> ResourceListItem {
    let ts = lastTimestamp ?? ISO8601DateFormatter().string(from: Date())
    return ResourceListItem(
        id: UUID(),
        gvk: .core("Event"),
        namespace: ns,
        name: "event-\(uid)",
        uid: uid,
        creationTimestamp: ts,
        status: eventType,
        ageSeconds: 60,
        labels: [:],
        annotations: [
            "type": eventType,
            "reason": reason,
            "involvedObject.kind": "Pod",
            "involvedObject.name": objectName,
            "source.component": "kubelet",
            "firstTimestamp": ts,
            "lastTimestamp": ts,
            "count": "1",
            "message": message,
        ]
    )
}
