// Tests/AppShellTests/NodesListViewModelTests.swift
// Coverage: NodesListViewModel load, projection, search filter, cordon/drain stubs.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - NodesListViewModelTests

@MainActor
final class NodesListViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = NodesListViewModel()
        XCTAssertTrue(sut.loadState.isIdle)
        XCTAssertNil(sut.selectedNodeName)
        XCTAssertTrue(sut.searchText.isEmpty)
    }

    // MARK: start — success path

    func test_start_projectsItemsIntoNodeRows() async {
        let items = [
            makeNodeItem(name: "node-1", status: "Ready", kubelet: "v1.29.3"),
            makeNodeItem(name: "node-2", status: "NotReady", kubelet: "v1.29.3"),
        ]
        let fake = FakeNodeListPort(items: items)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = NodesListViewModel()
            await sut.start(clusterId: ClusterId("prod"))
            let rows = sut.loadState.value
            XCTAssertEqual(rows?.count, 2)
            XCTAssertEqual(rows?.first?.name, "node-1")
            XCTAssertEqual(rows?.first?.status, "Ready")
        }
    }

    func test_start_sendsNoNamespaceToPort() async {
        let fake = FakeNodeListPort(items: [])
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = NodesListViewModel()
            await sut.start(clusterId: ClusterId("c"))
            // Nodes are cluster-scoped; nil namespace must be sent to port.
            XCTAssertNil(fake.lastNamespace)
        }
    }

    // MARK: reload — failure

    func test_reload_setsFailureOnPortError() async {
        let fake = FakeNodeListPort(error: ResourceListError.unimplemented)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = NodesListViewModel()
            await sut.reload(clusterId: ClusterId("c"))
            XCTAssertNotNil(sut.loadState.error)
            XCTAssertNil(sut.loadState.value)
        }
    }

    // MARK: filteredRows — search

    func test_filteredRows_searchByName() async {
        let items = [
            makeNodeItem(name: "control-plane-01"),
            makeNodeItem(name: "worker-01"),
            makeNodeItem(name: "worker-02"),
        ]
        let fake = FakeNodeListPort(items: items)
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = NodesListViewModel()
            await sut.start(clusterId: ClusterId("c"))
            sut.searchText = "worker"
            XCTAssertEqual(sut.filteredRows.count, 2)
            XCTAssertTrue(sut.filteredRows.allSatisfy { $0.name.contains("worker") })
        }
    }

    func test_filteredRows_emptySearchReturnsAll() async {
        let fake = FakeNodeListPort(items: [makeNodeItem(name: "n1"), makeNodeItem(name: "n2")])
        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = NodesListViewModel()
            await sut.start(clusterId: ClusterId("c"))
            sut.searchText = ""
            XCTAssertEqual(sut.filteredRows.count, 2)
        }
    }

    // MARK: cordon / drain stubs

    func test_cordon_doesNotCrash() {
        let sut = NodesListViewModel()
        // Must not crash — stub implementation logs and returns.
        sut.cordon(nodeName: "worker-01")
    }

    func test_drain_doesNotCrash() {
        let sut = NodesListViewModel()
        sut.drain(nodeName: "worker-01")
    }
}

// MARK: - Test doubles

private final class FakeNodeListPort: KubernetesResourceListPort, @unchecked Sendable {
    let stubbedItems: [ResourceListItem]
    let stubbedError: Error?
    private(set) var lastNamespace: String? = "UNSET"
    private var namespaceCaptured = false

    init(items: [ResourceListItem] = [], error: Error? = nil) {
        self.stubbedItems = items
        self.stubbedError = error
    }

    func list(gvk: GroupVersionKind, namespace: String?, clusterId: ClusterId) async throws -> [ResourceListItem] {
        lastNamespace = namespace
        namespaceCaptured = true
        if let error = stubbedError { throw error }
        return stubbedItems
    }

    func get(gvk: GroupVersionKind, name: String, namespace: String?, clusterId: ClusterId) async throws -> ResourceDetail {
        throw ResourceListError.unimplemented
    }
}

// MARK: - Helpers

private func makeNodeItem(
    name: String,
    status: String = "Ready",
    kubelet: String = "v1.29.3"
) -> ResourceListItem {
    ResourceListItem(
        id: UUID(),
        gvk: .core("Node"),
        namespace: nil,
        name: name,
        uid: UUID().uuidString,
        creationTimestamp: "2026-01-01T00:00:00Z",
        status: status,
        ageSeconds: 86400,
        labels: [:],
        annotations: ["status.nodeInfo.kubeletVersion": kubelet]
    )
}
