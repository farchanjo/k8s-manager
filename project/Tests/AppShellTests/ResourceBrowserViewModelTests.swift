// Tests/AppShellTests/ResourceBrowserViewModelTests.swift
// Coverage: ResourceBrowserViewModel list loading and selection flows.

import XCTest
import Dependencies
@testable import AppShell
import ClusterConnectivity
import ResourceBrowser
import SharedKernel

// MARK: - ResourceBrowserViewModelTests

@MainActor
final class ResourceBrowserViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdleWithDefaultKind() {
        let sut = ResourceBrowserViewModel()
        XCTAssertTrue(sut.resources.isIdle)
        XCTAssertEqual(sut.selectedKind, "Pod")
        XCTAssertNil(sut.selectedItem)
    }

    // MARK: load — success path

    func test_load_setsSuccessOnValidResponse() async {
        let expectedItems = [makeListItem(name: "pod-alpha"), makeListItem(name: "pod-beta")]
        let fake = FakeResourceListPort(items: expectedItems)

        await withDependencies {
            $0.kubernetesResourceList = fake
            $0.kubeconfigLoader = FakeKubeconfigLoaderPort(currentContext: "test-ctx", cluster: "test-cluster")
        } operation: {
            let sut = ResourceBrowserViewModel()
            await sut.load(kind: "Pod", namespace: nil)
            XCTAssertEqual(sut.resources, .success(expectedItems))
            XCTAssertEqual(sut.selectedKind, "Pod")
        }
    }

    func test_load_filtersNamespaceCorrectly() async {
        let fake = FakeResourceListPort(items: [makeListItem(name: "pod-ns", namespace: "kube-system")])

        await withDependencies {
            $0.kubernetesResourceList = fake
            $0.kubeconfigLoader = FakeKubeconfigLoaderPort(currentContext: "test-ctx", cluster: "test-cluster")
        } operation: {
            let sut = ResourceBrowserViewModel()
            await sut.load(kind: "Pod", namespace: "kube-system")
            XCTAssertEqual(fake.lastNamespace, "kube-system")
        }
    }

    // MARK: load — failure path

    func test_load_setsFailureWhenPortThrows() async {
        let fake = FakeResourceListPort(error: ResourceListError.unimplemented)

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ResourceBrowserViewModel()
            await sut.load(kind: "Pod", namespace: nil)
            XCTAssertNotNil(sut.resources.error)
            XCTAssertNil(sut.resources.value)
        }
    }

    // MARK: select

    func test_select_updatesSelectedItem() async {
        let item = makeListItem(name: "selected-pod")
        let fake = FakeResourceListPort(items: [item])

        await withDependencies {
            $0.kubernetesResourceList = fake
        } operation: {
            let sut = ResourceBrowserViewModel()
            await sut.load(kind: "Pod", namespace: nil)
            sut.select(item)
            XCTAssertEqual(sut.selectedItem, item)
        }
    }

    func test_select_nil_clearsSelection() {
        let sut = ResourceBrowserViewModel()
        sut.select(makeListItem(name: "pod-x"))
        sut.select(nil)
        XCTAssertNil(sut.selectedItem)
    }
}

// MARK: - Test doubles

/// Thread-safe fake that records the last namespace argument for assertion.
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

/// Minimal fake kubeconfig loader that returns a single context entry.
private struct FakeKubeconfigLoaderPort: KubeconfigLoaderPort {
    let currentContext: String
    let cluster: String

    func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        Kubeconfig(
            sourcePath: path,
            sourceMTimeRFC3339: "2024-01-01T00:00:00Z",
            currentContext: currentContext,
            contexts: [KubeconfigContext(name: currentContext, cluster: cluster, user: "test-user")]
        )
    }

    func contexts(in config: Kubeconfig) -> [KubeconfigContext] { config.contexts }

    func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }
}

// MARK: - Helpers

private func makeListItem(
    name: String,
    namespace: String? = "default"
) -> ResourceListItem {
    ResourceListItem(
        id: UUID(),
        gvk: .core("Pod"),
        namespace: namespace,
        name: name,
        uid: UUID().uuidString,
        creationTimestamp: "2026-01-01T00:00:00Z",
        status: "Running",
        ageSeconds: 3600
    )
}
