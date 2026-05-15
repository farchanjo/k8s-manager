// Tests/AppShellTests/ClusterListViewModelTests.swift
// Coverage: ClusterListViewModel kubeconfig load + health probe flows.

import XCTest
import Dependencies
@testable import AppShell
import ClusterConnectivity
import SharedKernel

// MARK: - ClusterListViewModelTests

@MainActor
final class ClusterListViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = ClusterListViewModel()
        XCTAssertTrue(sut.contexts.isIdle)
        XCTAssertTrue(sut.healthByContext.isEmpty)
    }

    // MARK: loadKubeconfig

    func test_loadKubeconfig_setsContextsOnSuccess() async {
        let expected = [
            KubeconfigContext(name: "prod", cluster: "prod-cluster", user: "admin"),
            KubeconfigContext(name: "staging", cluster: "stg-cluster", user: "dev"),
        ]
        let fakeLoader = FakeKubeconfigLoader(contexts: expected)

        await withDependencies {
            $0.kubeconfigLoader = fakeLoader
        } operation: {
            let sut = ClusterListViewModel()
            await sut.loadKubeconfig()
            XCTAssertEqual(sut.contexts, .success(expected))
        }
    }

    func test_loadKubeconfig_setsFailureOnError() async {
        let fakeLoader = FakeKubeconfigLoader(error: KubeconfigLoadError.parseError(detail: "bad yaml"))

        await withDependencies {
            $0.kubeconfigLoader = fakeLoader
        } operation: {
            let sut = ClusterListViewModel()
            await sut.loadKubeconfig()
            XCTAssertNotNil(sut.contexts.error)
            XCTAssertNil(sut.contexts.value)
        }
    }

    // MARK: probeHealth

    func test_probeHealth_setsHealthStatusOnSuccess() async {
        let context = KubeconfigContext(name: "prod", cluster: "prod-cluster", user: "admin")
        let expectedStatus = HealthStatus(
            clusterId: ClusterId("prod-cluster"),
            probedAt: "2026-01-01T00:00:00Z",
            state: .reachable,
            latencyMillis: 42
        )
        let fakeApi = FakeKubernetesApi(status: expectedStatus)
        let fakeLoader = FakeKubeconfigLoader(contexts: [context])

        await withDependencies {
            $0.kubeconfigLoader = fakeLoader
            $0.kubernetesApi = fakeApi
        } operation: {
            let sut = ClusterListViewModel()
            await sut.loadKubeconfig()
            await sut.probeHealth(for: context)
            XCTAssertEqual(sut.healthByContext["prod"], .success(expectedStatus))
        }
    }

    func test_probeHealth_setsFailureOnError() async {
        let context = KubeconfigContext(name: "dev", cluster: "dev-cluster", user: "ops")
        let fakeApi = FakeKubernetesApi(error: KubernetesApiError.transportError(detail: "timeout"))
        let fakeLoader = FakeKubeconfigLoader(contexts: [context])

        await withDependencies {
            $0.kubeconfigLoader = fakeLoader
            $0.kubernetesApi = fakeApi
        } operation: {
            let sut = ClusterListViewModel()
            await sut.loadKubeconfig()
            await sut.probeHealth(for: context)
            let resource = sut.healthByContext["dev"]
            XCTAssertNotNil(resource?.error)
            XCTAssertNil(resource?.value)
        }
    }
}

// MARK: - Test doubles

private struct FakeKubeconfigLoader: KubeconfigLoaderPort {
    let stubbedContexts: [KubeconfigContext]
    let stubbedError: Error?

    init(contexts: [KubeconfigContext] = [], error: Error? = nil) {
        self.stubbedContexts = contexts
        self.stubbedError = error
    }

    func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        if let error = stubbedError { throw error }
        return Kubeconfig(
            sourcePath: path,
            sourceMTimeRFC3339: "2026-01-01T00:00:00Z",
            contexts: stubbedContexts
        )
    }

    func contexts(in config: Kubeconfig) -> [KubeconfigContext] {
        config.contexts
    }

    func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }
}

private struct FakeKubernetesApi: KubernetesApiPort {
    let stubbedStatus: HealthStatus?
    let stubbedError: Error?

    init(status: HealthStatus? = nil, error: Error? = nil) {
        self.stubbedStatus = status
        self.stubbedError = error
    }

    func probeHealth(clusterId: ClusterId) async throws -> HealthStatus {
        if let error = stubbedError { throw error }
        return stubbedStatus!
    }

    func serverVersion(clusterId: ClusterId) async throws -> String {
        throw KubernetesApiError.unimplemented
    }
}
