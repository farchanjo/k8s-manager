// Tests/AppShellTests/Resources/Workloads/PodsListViewModelTests.swift
// Coverage: PodsListViewModel — idle state, load success, load failure, selection,
//           namespace filter, age string formatting.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - PodsListViewModelTests

@MainActor
final class PodsListViewModelTests: XCTestCase {

    private let testCluster = ClusterId("test-cluster")

    // MARK: Initial state

    func test_initialState_isIdleWithEmptyRows() {
        let sut = PodsListViewModel()
        XCTAssertTrue(sut.loadState.isIdle)
        XCTAssertTrue(sut.rows.isEmpty)
        XCTAssertNil(sut.selectedId)
    }

    // MARK: start → load success

    func test_start_setsSuccessStateAndPopulatesRows() async {
        let items = [makeListItem(name: "pod-alpha"), makeListItem(name: "pod-beta")]
        let fake = FakeResourceListPort(items: items)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = PodsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            XCTAssertEqual(sut.rows.count, 2)
            XCTAssertEqual(sut.rows.map(\.name).sorted(), ["pod-alpha", "pod-beta"])
            guard case .success(let count) = sut.loadState else {
                XCTFail("Expected .success, got \(sut.loadState)")
                return
            }
            XCTAssertEqual(count, 2)
        }
    }

    // MARK: load failure

    func test_reload_setsFailureWhenPortThrows() async {
        let fake = FakeResourceListPort(error: ResourceListError.unimplemented)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = PodsListViewModel()
            await sut.reload(clusterId: testCluster)
            XCTAssertNotNil(sut.loadState.error)
            XCTAssertTrue(sut.rows.isEmpty)
        }
    }

    // MARK: namespace filter

    func test_start_passesNamespaceToPort() async {
        let fake = FakeResourceListPort(items: [makeListItem(name: "scoped-pod")])

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = PodsListViewModel()
            await sut.start(clusterId: testCluster, namespace: "kube-system")
            XCTAssertEqual(fake.lastNamespace, "kube-system")
            XCTAssertEqual(sut.namespace, "kube-system")
        }
    }

    // MARK: selection

    func test_selectedId_isNilAfterLoad() async {
        let fake = FakeResourceListPort(items: [makeListItem(name: "pod-x")])

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = PodsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            XCTAssertNil(sut.selectedId)
        }
    }

    func test_selectedId_canBeSetToExistingRowUid() async {
        let item = makeListItem(name: "target-pod", uid: "uid-123")
        let fake = FakeResourceListPort(items: [item])

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = PodsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            sut.selectedId = "uid-123"
            XCTAssertEqual(sut.selectedId, "uid-123")
        }
    }

    // MARK: age string formatting

    func test_ageString_formatsCorrectly() {
        XCTAssertEqual(PodsListViewModel.ageString(seconds: 45), "45s")
        XCTAssertEqual(PodsListViewModel.ageString(seconds: 90), "1m")
        XCTAssertEqual(PodsListViewModel.ageString(seconds: 7200), "2h")
        XCTAssertEqual(PodsListViewModel.ageString(seconds: 172800), "2d")
    }

    // MARK: search filter

    func test_filteredRows_filtersOnName() async {
        let items = [
            makeListItem(name: "alpha-pod"),
            makeListItem(name: "beta-pod"),
        ]
        let fake = FakeResourceListPort(items: items)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = PodsListViewModel()
            await sut.start(clusterId: testCluster, namespace: nil)
            sut.searchText = "alpha"
            XCTAssertEqual(sut.filteredRows.count, 1)
            XCTAssertEqual(sut.filteredRows.first?.name, "alpha-pod")
        }
    }
}

// MARK: - Test doubles

/// Thread-safe fake that captures the last namespace argument for assertion.
private final class FakeResourceListPort: KubernetesResourceListPort, @unchecked Sendable {
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
        gvk: .core("Pod"),
        namespace: namespace,
        name: name,
        uid: uid,
        creationTimestamp: "2026-01-01T00:00:00Z",
        status: "Running",
        ageSeconds: 3600
    )
}
