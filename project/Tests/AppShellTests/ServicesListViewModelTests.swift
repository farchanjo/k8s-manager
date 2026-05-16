// Tests/AppShellTests/ServicesListViewModelTests.swift
// Coverage: ServicesListViewModel load, filter, and error paths.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - ServicesListViewModelTests

@MainActor
final class ServicesListViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = ServicesListViewModel()
        XCTAssertTrue(sut.loadState.isIdle)
        XCTAssertNil(sut.namespace)
        XCTAssertTrue(sut.searchText.isEmpty)
    }

    // MARK: start — success path

    func test_start_setsSuccessWithReturnedItems() async {
        let expected = [
            makeItem(name: "svc-alpha", namespace: "default"),
            makeItem(name: "svc-beta", namespace: "kube-system"),
        ]
        let fake = FakeListPort(items: expected)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ServicesListViewModel()
            await sut.start(clusterId: ClusterId("test-cluster"), namespace: nil)
            XCTAssertEqual(sut.loadState.value?.count, 2)
            XCTAssertEqual(sut.loadState.value?.first?.name, "svc-alpha")
        }
    }

    func test_start_storesNamespaceFilter() async {
        let fake = FakeListPort(items: [])
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ServicesListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: "kube-system")
            XCTAssertEqual(sut.namespace, "kube-system")
            XCTAssertEqual(fake.lastNamespace, "kube-system")
        }
    }

    // MARK: reload — failure path

    func test_reload_setsFailureWhenPortThrows() async {
        let fake = FakeListPort(error: ResourceListError.unimplemented)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ServicesListViewModel()
            await sut.reload(clusterId: ClusterId("c"))
            XCTAssertNotNil(sut.loadState.error)
            XCTAssertNil(sut.loadState.value)
        }
    }

    // MARK: filteredRows — search

    func test_filteredRows_returnsAllWhenSearchEmpty() async {
        let items = [makeItem(name: "nginx"), makeItem(name: "postgres")]
        let fake = FakeListPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ServicesListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            sut.searchText = ""
            XCTAssertEqual(sut.filteredRows.count, 2)
        }
    }

    func test_filteredRows_appliesSearchByName() async {
        let items = [makeItem(name: "nginx"), makeItem(name: "postgres")]
        let fake = FakeListPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ServicesListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            sut.searchText = "ngin"
            XCTAssertEqual(sut.filteredRows.count, 1)
            XCTAssertEqual(sut.filteredRows.first?.name, "nginx")
        }
    }

    func test_filteredRows_caseInsensitiveSearch() async {
        let items = [makeItem(name: "MyService", namespace: "Prod")]
        let fake = FakeListPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ServicesListViewModel()
            await sut.start(clusterId: ClusterId("c"), namespace: nil)
            sut.searchText = "myservice"
            XCTAssertEqual(sut.filteredRows.count, 1)
        }
    }
}

// MARK: - Test doubles

private final class FakeListPort: KubernetesResourceListPort, @unchecked Sendable {
    let stubbedItems: [ResourceListItem]
    let stubbedError: Error?
    private(set) var lastNamespace: String?

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

private func makeItem(name: String, namespace: String? = "default") -> ResourceListItem {
    ResourceListItem(
        id: UUID(),
        gvk: .core("Service"),
        namespace: namespace,
        name: name,
        uid: UUID().uuidString,
        creationTimestamp: "2026-01-01T00:00:00Z",
        status: "active",
        ageSeconds: 7200
    )
}
