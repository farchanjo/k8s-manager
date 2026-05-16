// Tests/AppShellTests/Resources/Config/SecretsListViewModelTests.swift
// Coverage: SecretsListViewModel fetch, failure, revealData, and requestDelete flows.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - SecretsListViewModelTests

@MainActor
final class SecretsListViewModelTests: XCTestCase {

    private let clusterId = ClusterId("test-cluster")

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = SecretsListViewModel()
        XCTAssertTrue(sut.loadState.isIdle)
        XCTAssertTrue(sut.rows.isEmpty)
        XCTAssertNil(sut.selectedId)
        XCTAssertFalse(sut.showRevealSheet)
        XCTAssertFalse(sut.showDeleteConfirm)
    }

    // MARK: start — success

    func test_start_success_populatesRows() async {
        let items = [
            makeItem(name: "tls-secret", namespace: "default"),
            makeItem(name: "registry-token", namespace: "kube-system"),
        ]
        await withDependencies {
            $0.kubernetesResourceList = FakeSecretListPort(items: items)
        } operation: {
            let sut = SecretsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            XCTAssertEqual(sut.rows.count, 2)
            XCTAssertEqual(sut.rows[0].name, "tls-secret")
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
            $0.kubernetesResourceList = FakeSecretListPort(
                error: ResourceListError.transportError(detail: "network unreachable")
            )
        } operation: {
            let sut = SecretsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            XCTAssertTrue(sut.rows.isEmpty)
            XCTAssertNotNil(sut.loadState.error)
        }
    }

    // MARK: revealData

    func test_revealData_setsRevealRowAndOpensSheet() async {
        let items = [makeItem(name: "api-key", namespace: "production")]
        await withDependencies {
            $0.kubernetesResourceList = FakeSecretListPort(items: items)
        } operation: {
            let sut = SecretsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            let row = sut.rows[0]
            sut.revealData(row)
            XCTAssertTrue(sut.showRevealSheet)
            XCTAssertEqual(sut.revealRow?.name, "api-key")
        }
    }

    // MARK: requestDelete

    func test_requestDelete_setPendingRowAndFlag() async {
        let items = [makeItem(name: "old-secret", namespace: "staging")]
        await withDependencies {
            $0.kubernetesResourceList = FakeSecretListPort(items: items)
        } operation: {
            let sut = SecretsListViewModel()
            await sut.start(clusterId: clusterId, namespace: nil)
            let row = sut.rows[0]
            sut.requestDelete(row)
            XCTAssertTrue(sut.showDeleteConfirm)
            XCTAssertEqual(sut.pendingDeleteRow?.name, "old-secret")
        }
    }

    // MARK: namespace filter

    func test_start_withNamespace_passesNamespaceToPort() async {
        var capturedNamespace: String? = "unset"
        await withDependencies {
            $0.kubernetesResourceList = FakeSecretListPort(
                items: [],
                onList: { ns in capturedNamespace = ns }
            )
        } operation: {
            let sut = SecretsListViewModel()
            await sut.start(clusterId: clusterId, namespace: "production")
            XCTAssertEqual(capturedNamespace, "production")
            XCTAssertEqual(sut.namespace, "production")
        }
    }

    // MARK: Helpers

    private func makeItem(name: String, namespace: String) -> ResourceListItem {
        ResourceListItem(
            id: UUID(),
            gvk: .core("Secret"),
            namespace: namespace,
            name: name,
            uid: UUID().uuidString,
            creationTimestamp: "2026-01-01T00:00:00Z",
            status: "Active",
            ageSeconds: 7200
        )
    }
}

// MARK: - FakeSecretListPort (local test double)

private final class FakeSecretListPort: KubernetesResourceListPort {
    private let stubbedItems: [ResourceListItem]
    private let stubbedError: Error?
    private let onList: ((String?) -> Void)?

    init(
        items: [ResourceListItem],
        error: Error? = nil,
        onList: ((String?) -> Void)? = nil
    ) {
        stubbedItems = items
        stubbedError = error
        self.onList = onList
    }

    init(error: Error) {
        stubbedItems = []
        stubbedError = error
        onList = nil
    }

    func list(gvk: GroupVersionKind, namespace: String?, clusterId: ClusterId) async throws -> [ResourceListItem] {
        onList?(namespace)
        if let error = stubbedError { throw error }
        return stubbedItems
    }

    func get(gvk: GroupVersionKind, name: String, namespace: String?, clusterId: ClusterId) async throws -> ResourceDetail {
        throw ResourceListError.unimplemented
    }
}
