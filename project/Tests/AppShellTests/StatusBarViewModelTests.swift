// Tests/AppShellTests/StatusBarViewModelTests.swift
// Coverage: StatusBarViewModel state transitions, port failure handling,
//           ConnectionBadge mapping, and error ring buffer.

import XCTest
import Dependencies
@testable import AppShell
import ClusterConnectivity
import MetricsObservability
import SharedKernel

// MARK: - StatusBarViewModelTests

@MainActor
final class StatusBarViewModelTests: XCTestCase {

    // MARK: Initial state

    /// New `StatusBarViewModel` exposes placeholder strings for all text fields.
    func test_initialState_hasPlaceholders() {
        let sut = StatusBarViewModel()
        XCTAssertEqual(sut.clusterName, "—")
        XCTAssertEqual(sut.serverVersion, "—")
        XCTAssertEqual(sut.connectionBadge, .unknown)
        XCTAssertNil(sut.cpuPercent)
        XCTAssertNil(sut.memPercent)
        XCTAssertEqual(sut.activeWatchCount, 0)
        XCTAssertEqual(sut.errorCount, 0)
    }

    // MARK: Successful probe

    /// After a successful probe the view model reflects the cluster name and server version.
    func test_refresh_populatesClusterNameAndVersion_onSuccess() async {
        let context = KubeconfigContext(name: "staging", cluster: "stg-cluster", user: "dev")
        let fakeLoader = FakeStatusBarKubeconfigLoader(contexts: [context], activeContext: context)
        let fakeApi = FakeStatusBarKubernetesApi(
            state: .reachable,
            version: "v1.31.2"
        )

        await withDependencies {
            $0.kubeconfigLoader = fakeLoader
            $0.kubernetesApi = fakeApi
        } operation: {
            let sut = StatusBarViewModel()
            await sut.refresh()
            XCTAssertEqual(sut.clusterName, "staging")
            XCTAssertEqual(sut.serverVersion, "v1.31.2")
            XCTAssertEqual(sut.connectionBadge, .connected)
        }
    }

    // MARK: Port failure — graceful degradation

    /// When the kubeconfig port throws, all fields fall back to placeholders with no crash.
    func test_refresh_gracefullyDegrades_onPortFailure() async {
        let fakeLoader = FakeStatusBarKubeconfigLoader(
            contexts: [],
            activeContext: nil,
            error: KubeconfigLoadError.ioError(path: "~/.kube/config", underlying: "ENOENT")
        )

        await withDependencies {
            $0.kubeconfigLoader = fakeLoader
        } operation: {
            let sut = StatusBarViewModel()
            await sut.refresh()
            XCTAssertEqual(sut.clusterName, "—")
            XCTAssertEqual(sut.serverVersion, "—")
            XCTAssertEqual(sut.connectionBadge, .unknown)
            XCTAssertNil(sut.cpuPercent)
            XCTAssertNil(sut.memPercent)
        }
    }

    // MARK: ConnectionBadge mapping

    /// `ConnectionBadge.init(from:)` maps each `HealthState` to the correct badge value.
    func test_connectionBadge_mapsHealthStatesCorrectly() {
        XCTAssertEqual(StatusBarViewModel.ConnectionBadge(from: .reachable),    .connected)
        XCTAssertEqual(StatusBarViewModel.ConnectionBadge(from: .degraded),     .degraded)
        XCTAssertEqual(StatusBarViewModel.ConnectionBadge(from: .unreachable),  .disconnected)
        XCTAssertEqual(StatusBarViewModel.ConnectionBadge(from: .unauthorized), .disconnected)
        XCTAssertEqual(StatusBarViewModel.ConnectionBadge(from: .forbidden),    .degraded)
        XCTAssertEqual(StatusBarViewModel.ConnectionBadge(from: .unknown),      .unknown)
    }

    // MARK: Error ring buffer

    /// `recordError()` increments `errorCount`; `pruneErrors()` evicts old entries.
    func test_errorRing_countsAndPrunesErrors() {
        let sut = StatusBarViewModel()
        XCTAssertEqual(sut.errorCount, 0, "Expected zero errors initially")

        sut.recordError()
        sut.recordError()
        XCTAssertEqual(sut.errorCount, 2, "Expected two errors after two records")

        // Calling pruneErrors when entries are fresh must keep them.
        sut.pruneErrors()
        XCTAssertEqual(sut.errorCount, 2, "Fresh errors must survive pruning")
    }
}

// MARK: - Test doubles

private struct FakeStatusBarKubeconfigLoader: KubeconfigLoaderPort {
    let stubbedContexts: [KubeconfigContext]
    let stubbedActiveContext: KubeconfigContext?
    let stubbedError: Error?

    init(
        contexts: [KubeconfigContext],
        activeContext: KubeconfigContext?,
        error: Error? = nil
    ) {
        self.stubbedContexts = contexts
        self.stubbedActiveContext = activeContext
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

    func contexts(in config: Kubeconfig) -> [KubeconfigContext] { config.contexts }

    func activeContext(in config: Kubeconfig) -> KubeconfigContext? { stubbedActiveContext }
}

private struct FakeStatusBarKubernetesApi: KubernetesApiPort {
    let stubbedState: HealthState
    let stubbedVersion: String

    init(state: HealthState, version: String) {
        self.stubbedState = state
        self.stubbedVersion = version
    }

    func probeHealth(clusterId: ClusterId) async throws -> HealthStatus {
        HealthStatus(
            clusterId: clusterId,
            probedAt: "2026-01-01T00:00:00Z",
            state: stubbedState
        )
    }

    func serverVersion(clusterId: ClusterId) async throws -> String { stubbedVersion }
}
