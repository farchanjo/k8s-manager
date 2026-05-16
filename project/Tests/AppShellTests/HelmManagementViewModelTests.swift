// Tests/AppShellTests/HelmManagementViewModelTests.swift
// Coverage: HelmManagementViewModel load, history, and rollback flows.

import XCTest
import Dependencies
@testable import AppShell
import HelmManagement
import SharedKernel

// MARK: - HelmManagementViewModelTests

@MainActor
final class HelmManagementViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = HelmManagementViewModel()
        XCTAssertTrue(sut.releases.isIdle)
        XCTAssertTrue(sut.history.isEmpty)
        XCTAssertNil(sut.selectedRelease)
        XCTAssertFalse(sut.rollbackInProgress)
    }

    // MARK: loadReleases

    func test_loadReleases_setsSuccessOnLoad() async {
        let expected = [makeRelease(name: "nginx", version: 3)]
        let fakeStore = FakeHelmReleaseStore(releases: expected)

        await withDependencies {
            $0.helmReleaseStore = fakeStore
        } operation: {
            let sut = HelmManagementViewModel()
            await sut.loadReleases()
            XCTAssertEqual(sut.releases.value?.count, 1)
            XCTAssertEqual(sut.releases.value?.first?.name, "nginx")
        }
    }

    func test_loadReleases_setsFailureOnError() async {
        let fakeStore = FakeHelmReleaseStore(error: HelmReleaseStoreError.unimplemented)

        await withDependencies {
            $0.helmReleaseStore = fakeStore
        } operation: {
            let sut = HelmManagementViewModel()
            await sut.loadReleases()
            XCTAssertNotNil(sut.releases.error)
            XCTAssertNil(sut.releases.value)
        }
    }

    // MARK: loadHistory

    func test_loadHistory_populatesHistoryKeyedByReleaseId() async {
        let release = makeRelease(name: "cert-manager", version: 2)
        let fakeStore = FakeHelmReleaseStore(releases: [release, makeRelease(name: "cert-manager", version: 1)])

        await withDependencies {
            $0.helmReleaseStore = fakeStore
        } operation: {
            let sut = HelmManagementViewModel()
            await sut.loadHistory(for: release)
            let key = release.id.uuidString
            XCTAssertEqual(sut.history[key]?.value?.count, 2)
            XCTAssertEqual(sut.history[key]?.value?.first?.revision, 2)
        }
    }

    // MARK: rollback

    func test_rollback_setsRollbackErrorWhenLeaseUnimplemented() async {
        let release = makeRelease(name: "prometheus", version: 5)
        let fakeStore = FakeHelmReleaseStore(releases: [release])

        await withDependencies {
            $0.helmReleaseStore = fakeStore
            $0.rollbackLease = UnimplementedRollbackLeasePort()
            $0.serverSideApply = UnimplementedServerSideApplyPort()
        } operation: {
            let sut = HelmManagementViewModel()
            await sut.rollback(release: release, to: 4)
            XCTAssertNotNil(sut.rollbackError)
            XCTAssertFalse(sut.rollbackInProgress)
        }
    }

    func test_rollback_clearsInProgressOnCompletion() async {
        let release = makeRelease(name: "grafana", version: 2)
        let fakeStore = FakeHelmReleaseStore(releases: [release])

        await withDependencies {
            $0.helmReleaseStore = fakeStore
            $0.rollbackLease = UnimplementedRollbackLeasePort()
            $0.serverSideApply = UnimplementedServerSideApplyPort()
        } operation: {
            let sut = HelmManagementViewModel()
            await sut.rollback(release: release, to: 1)
            // rollbackInProgress must be false regardless of outcome
            XCTAssertFalse(sut.rollbackInProgress)
        }
    }
}

// MARK: - Test doubles

private struct FakeHelmReleaseStore: HelmReleaseStorePort {
    let stubbedReleases: [Release]
    let stubbedError: Error?

    init(releases: [Release] = [], error: Error? = nil) {
        self.stubbedReleases = releases
        self.stubbedError = error
    }

    func listReleases(clusterId: ClusterId, namespace: String?) async throws -> [Release] {
        if let error = stubbedError { throw error }
        if let namespace {
            return stubbedReleases.filter { $0.namespace == namespace }
        }
        return stubbedReleases
    }

    func readRelease(secretName: String, namespace: String, clusterId: ClusterId) async throws -> Release {
        throw HelmReleaseStoreError.unimplemented
    }

    func writeRelease(_ release: Release, clusterId: ClusterId) async throws {
        throw HelmReleaseStoreError.unimplemented
    }
}

// MARK: - Fixture helpers

private func makeRelease(name: String, version: Int) -> Release {
    Release(
        id: UUID(),
        kubernetesContextId: UUID(),
        name: name,
        namespace: "default",
        version: version,
        status: .deployed,
        chart: ChartMetadata(
            name: name,
            version: "1.0.\(version)",
            appVersion: "v\(version)",
            apiVersion: .v2,
            description: "Test chart",
            type: .application,
            icon: nil,
            dependencies: [],
            maintainers: [],
            home: nil,
            sources: []
        ),
        info: ReleaseInfo(
            firstDeployed: "2026-01-01T00:00:00Z",
            lastDeployed: "2026-01-0\(version)T00:00:00Z",
            deleted: nil,
            description: "Install complete",
            status: .deployed,
            notes: ""
        ),
        manifestYAML: "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: test",
        valuesJSON: "{}",
        hooks: [],
        modifiedAtRFC3339: "2026-01-0\(version)T00:00:00Z",
        sourceSecretName: "sh.helm.release.v1.\(name).v\(version)"
    )
}
