// Tests/AppShellTests/Resources/Config/ConfigMapsListViewModelTests.swift
// Coverage: ConfigMapsListViewModel fetch, failure, and requestDelete flows.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - ConfigMapsListViewModelTests

@MainActor
final class ConfigMapsListViewModelTests: XCTestCase {

    private let clusterId = ClusterId("test-cluster")

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = ConfigMapsListViewModel()
        XCTAssertTrue(sut.loadState.isIdle)
        XCTAssertTrue(sut.rows.isEmpty)
        XCTAssertNil(sut.selectedId)
    }

    // MARK: start — success

    func test_start_success_populatesRows() async {
        let items = [
            makeItem(name: "app-config", namespace: "default"),
            makeItem(name: "db-config", namespace: "kube-system"),
        ]
        await withDependencies {
            $0.kubernetesResourceList = FakeResourceListPort(items: items)
        } operation: {
            let sut = ConfigMapsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            XCTAssertEqual(sut.rows.count, 2)
            XCTAssertEqual(sut.rows[0].name, "app-config")
            XCTAssertEqual(sut.rows[1].namespace, "kube-system")
            if case .success(let count) = sut.loadState {
                XCTAssertEqual(count, 2)
            } else {
                XCTFail("Expected .success loadState")
            }
        }
    }

    // MARK: start — failure

    func test_start_failure_setsFailureState() async {
        await withDependencies {
            $0.kubernetesResourceList = FakeResourceListPort(
                error: ResourceListError.transportError(detail: "timeout")
            )
        } operation: {
            let sut = ConfigMapsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            XCTAssertTrue(sut.rows.isEmpty)
            XCTAssertNotNil(sut.loadState.error)
        }
    }

    // MARK: requestDelete

    func test_requestDelete_setPendingRowAndFlag() async {
        let items = [makeItem(name: "cm-a", namespace: "default")]
        await withDependencies {
            $0.kubernetesResourceList = FakeResourceListPort(items: items)
        } operation: {
            let sut = ConfigMapsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            let row = sut.rows[0]
            sut.requestDelete(row)
            XCTAssertTrue(sut.showDeleteConfirm)
            XCTAssertEqual(sut.pendingDeleteRow?.name, "cm-a")
        }
    }

    // MARK: reload

    func test_reload_refreshesRows() async {
        let initial = [makeItem(name: "first", namespace: "default")]
        let updated = [
            makeItem(name: "first", namespace: "default"),
            makeItem(name: "second", namespace: "default"),
        ]
        var callCount = 0
        await withDependencies {
            $0.kubernetesResourceList = FakeResourceListPort(
                itemsProvider: {
                    callCount += 1
                    return callCount == 1 ? initial : updated
                }
            )
        } operation: {
            let sut = ConfigMapsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            XCTAssertEqual(sut.rows.count, 1)
            await sut.reload(clusterId: clusterId)
            XCTAssertEqual(sut.rows.count, 2)
        }
    }

    // MARK: Helpers

    private func makeItem(name: String, namespace: String) -> ResourceListItem {
        ResourceListItem(
            id: UUID(),
            gvk: .core("ConfigMap"),
            namespace: namespace,
            name: name,
            uid: UUID().uuidString,
            creationTimestamp: "2026-01-01T00:00:00Z",
            status: "Active",
            ageSeconds: 3600
        )
    }
}

// MARK: - FakeResourceListPort (local test double)

private final class FakeResourceListPort: KubernetesResourceListPort, @unchecked Sendable {
    private let stubbedError: Error?
    private let itemsProvider: (() -> [ResourceListItem])?
    private let stubbedItems: [ResourceListItem]

    init(items: [ResourceListItem]) {
        stubbedItems = items
        itemsProvider = nil
        stubbedError = nil
    }

    init(error: Error) {
        stubbedItems = []
        itemsProvider = nil
        stubbedError = error
    }

    init(itemsProvider: @escaping () -> [ResourceListItem]) {
        stubbedItems = []
        self.itemsProvider = itemsProvider
        stubbedError = nil
    }

    func list(gvk: GroupVersionKind, namespace: String?, clusterId: ClusterId) async throws -> [ResourceListItem] {
        if let error = stubbedError { throw error }
        return itemsProvider?() ?? stubbedItems
    }

    func get(gvk: GroupVersionKind, name: String, namespace: String?, clusterId: ClusterId) async throws -> ResourceDetail {
        throw ResourceListError.unimplemented
    }
}
