// Tests/AppShellTests/EventsListViewModelTests.swift
// Coverage: EventsListViewModel load, filter (type/search/objectKind), stop polling.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - EventsListViewModelTests

@MainActor
final class EventsListViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = EventsListViewModel()
        XCTAssertTrue(sut.loadState.isIdle)
        XCTAssertNil(sut.filter.typeFilter)
        XCTAssertTrue(sut.filter.searchText.isEmpty)
        XCTAssertNil(sut.filter.objectKindFilter)
    }

    // MARK: start — loads events

    func test_start_setsSuccessWithProjectedRows() async {
        let items = [
            makeEventItem(name: "e1", eventType: "Warning", reason: "BackOff", objectKind: "Pod"),
            makeEventItem(name: "e2", eventType: "Normal", reason: "Pulled", objectKind: "Pod"),
        ]
        let fake = FakeEventsPort(items: items)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = EventsListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            let rows = sut.loadState.value
            XCTAssertEqual(rows?.count, 2)
            XCTAssertEqual(rows?.first?.reason, "BackOff")
            XCTAssertTrue(rows?.first?.isWarning ?? false)
        }
    }

    func test_start_passesNamespaceToPort() async {
        let fake = FakeEventsPort(items: [])
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = EventsListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: "staging")
            XCTAssertEqual(fake.lastNamespace, "staging")
        }
    }

    // MARK: filteredRows — type filter

    func test_filteredRows_typeFilterWarningOnly() async {
        let items = [
            makeEventItem(name: "e1", eventType: "Warning", reason: "BackOff", objectKind: "Pod"),
            makeEventItem(name: "e2", eventType: "Normal", reason: "Pulled", objectKind: "Pod"),
        ]
        let fake = FakeEventsPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = EventsListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            sut.filter.typeFilter = "Warning"
            XCTAssertEqual(sut.filteredRows.count, 1)
            XCTAssertEqual(sut.filteredRows.first?.reason, "BackOff")
        }
    }

    func test_filteredRows_nilTypeFilterReturnsAll() async {
        let items = [
            makeEventItem(name: "e1", eventType: "Warning", reason: "BackOff", objectKind: "Pod"),
            makeEventItem(name: "e2", eventType: "Normal", reason: "Pulled", objectKind: "Pod"),
        ]
        let fake = FakeEventsPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = EventsListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            sut.filter.typeFilter = nil
            XCTAssertEqual(sut.filteredRows.count, 2)
        }
    }

    // MARK: filteredRows — search text

    func test_filteredRows_searchByReason() async {
        let items = [
            makeEventItem(name: "e1", eventType: "Warning", reason: "BackOff", objectKind: "Pod"),
            makeEventItem(name: "e2", eventType: "Normal", reason: "Scheduled", objectKind: "Pod"),
        ]
        let fake = FakeEventsPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = EventsListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            sut.filter.searchText = "back"
            XCTAssertEqual(sut.filteredRows.count, 1)
            XCTAssertEqual(sut.filteredRows.first?.reason, "BackOff")
        }
    }

    // MARK: filteredRows — objectKind filter

    func test_filteredRows_objectKindFilter() async {
        let items = [
            makeEventItem(name: "e1", eventType: "Normal", reason: "Pulled", objectKind: "Pod"),
            makeEventItem(name: "e2", eventType: "Normal", reason: "Scaled", objectKind: "Deployment"),
        ]
        let fake = FakeEventsPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = EventsListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            sut.filter.objectKindFilter = "Deployment"
            XCTAssertEqual(sut.filteredRows.count, 1)
            XCTAssertEqual(sut.filteredRows.first?.reason, "Scaled")
        }
    }

    // MARK: stop

    func test_stop_doesNotCrashWhenCalledBeforeStart() {
        let sut = EventsListViewModel()
        // Must not crash when stop is called before start.
        sut.stop()
    }

    // MARK: failure path

    func test_start_setsFailureOnError() async {
        let fake = FakeEventsPort(error: ResourceListError.unimplemented)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = EventsListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            XCTAssertNotNil(sut.loadState.error)
        }
    }
}

// MARK: - Test doubles

private final class FakeEventsPort: KubernetesResourceListPort, @unchecked Sendable {
    let stubbedItems: [ResourceListItem]
    let stubbedError: Error?
    private(set) var lastNamespace: String? = "UNSET"

    init(items: [ResourceListItem] = [], error: Error? = nil) {
        self.stubbedItems = items
        self.stubbedError = error
    }

    func list(gvk: GroupVersionKind, namespace: String?, clusterId: ClusterId) async throws -> [ResourceListItem] {
        lastNamespace = namespace
        if let error = stubbedError { throw error }
        return stubbedItems
    }

    func get(gvk: GroupVersionKind, name: String, namespace: String?, clusterId: ClusterId) async throws -> ResourceDetail {
        throw ResourceListError.unimplemented
    }
}

// MARK: - Helpers

private func makeEventItem(
    name: String,
    eventType: String,
    reason: String,
    objectKind: String
) -> ResourceListItem {
    ResourceListItem(
        id: UUID(),
        gvk: .core("Event"),
        namespace: "default",
        name: name,
        uid: UUID().uuidString,
        creationTimestamp: "2026-01-01T00:00:00Z",
        status: eventType,
        ageSeconds: 300,
        labels: [:],
        annotations: [
            "type": eventType,
            "reason": reason,
            "involvedObject.kind": objectKind,
            "involvedObject.name": "\(objectKind.lowercased())-abc",
            "source.component": "kubelet",
            "lastTimestamp": "2026-01-01T00:05:00Z",
            "count": "3",
            "message": "Test event message for \(reason)",
        ]
    )
}
