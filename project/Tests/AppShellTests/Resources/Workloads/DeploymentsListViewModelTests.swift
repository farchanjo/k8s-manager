// Tests/AppShellTests/Resources/Workloads/DeploymentsListViewModelTests.swift
// Coverage: DeploymentsListViewModel — idle, load success, load failure,
//           namespace forwarding, search filter.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - DeploymentsListViewModelTests

@MainActor
final class DeploymentsListViewModelTests: XCTestCase {

    private let testCluster = ClusterId("test-cluster")

    // MARK: Initial state

    func test_initialState_isIdleWithEmptyRows() {
        let sut = DeploymentsListViewModel()
        XCTAssertTrue(sut.loadState.isIdle)
        XCTAssertTrue(sut.rows.isEmpty)
        XCTAssertNil(sut.selectedId)
    }

    // MARK: start → load success

    func test_start_populatesRowsOnSuccess() async {
        let items = [
            makeListItem(name: "web-deploy"),
            makeListItem(name: "api-deploy"),
        ]
        let fake = FakeDeploymentListPort(items: items)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = DeploymentsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            XCTAssertEqual(sut.rows.count, 2)
            XCTAssertEqual(sut.rows.map(\.name).sorted(), ["api-deploy", "web-deploy"])
            XCTAssertFalse(sut.loadState.isLoading)
        }
    }

    // MARK: load failure

    func test_reload_setsFailureOnPortError() async {
        let fake = FakeDeploymentListPort(error: ResourceListError.unimplemented)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = DeploymentsListViewModel()
            await sut.reload(clusterId: testCluster)
            XCTAssertNotNil(sut.loadState.error)
            XCTAssertTrue(sut.rows.isEmpty)
        }
    }

    // MARK: namespace forwarding

    func test_start_forwardsNamespaceToPort() async {
        let fake = FakeDeploymentListPort(items: [makeListItem(name: "ns-deploy")])

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = DeploymentsListViewModel()
            await sut.start(clusterId: testCluster, namespace: "production")
            XCTAssertEqual(fake.lastNamespace, "production")
            XCTAssertEqual(sut.namespace, "production")
        }
    }

    // MARK: search filter

    func test_filteredRows_returnsAllWhenSearchTextEmpty() async {
        let items = [makeListItem(name: "foo"), makeListItem(name: "bar")]
        let fake = FakeDeploymentListPort(items: items)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = DeploymentsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            XCTAssertEqual(sut.filteredRows.count, 2)
        }
    }

    func test_filteredRows_filtersOnName() async {
        let items = [makeListItem(name: "frontend"), makeListItem(name: "backend")]
        let fake = FakeDeploymentListPort(items: items)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = DeploymentsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            sut.searchText = "front"
            XCTAssertEqual(sut.filteredRows.count, 1)
            XCTAssertEqual(sut.filteredRows.first?.name, "frontend")
        }
    }

    // MARK: namespace mutation triggers reload

    func test_namespaceChange_storesNewValue() async {
        let fake = FakeDeploymentListPort(items: [])

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = DeploymentsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            sut.namespace = "staging"
            XCTAssertEqual(sut.namespace, "staging")
        }
    }
}

// MARK: - Test doubles

private final class FakeDeploymentListPort: KubernetesResourceListPort, @unchecked Sendable {
    private let stubbedItems: [ResourceListItem]
    private let stubbedError: Error?
    private(set) var lastNamespace: String?

    init(items: [ResourceListItem] = [], error: Error? = nil) {
        self.stubbedItems = items
        self.stubbedError = error
    }

    func list(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> [ResourceListItem] {
        lastNamespace = namespace
        if let error = stubbedError { throw error }
        return stubbedItems
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

private func makeListItem(
    name: String,
    uid: String = UUID().uuidString,
    namespace: String? = "default"
) -> ResourceListItem {
    ResourceListItem(
        id: UUID(),
        gvk: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
        namespace: namespace,
        name: name,
        uid: uid,
        creationTimestamp: "2026-01-01T00:00:00Z",
        status: "Running",
        ageSeconds: 7200
    )
}
