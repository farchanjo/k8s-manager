// Tests/AppShellTests/ApplicationsViewModelTests.swift
// Coverage: ApplicationsViewModel — load, deduplication, sorting, row action, error path.
// ADR ref: ADR-0067 (applications cluster-scope view)

import XCTest
import Dependencies
@testable import AppShell
import HelmManagement
import SharedKernel

// MARK: - ApplicationsViewModelTests

@MainActor
final class ApplicationsViewModelTests: XCTestCase {

    // MARK: - start / load

    func test_start_setsSuccessWithDeduplicatedRows() async {
        // Two revisions of the same release — only latest should appear.
        let store = SpyApplicationsReleaseStore(releases: [
            makeRelease(name: "nginx", version: 3),
            makeRelease(name: "nginx", version: 1),
        ])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            let state = sut.viewState.value
            XCTAssertNotNil(state, "success state must be set")
            XCTAssertEqual(state?.releases.count, 1, "two revisions collapse to one row")
            XCTAssertEqual(state?.releases.first?.revision, 3, "latest revision wins")
        }
    }

    func test_start_excludesSupersededRevisions() async {
        let store = SpyApplicationsReleaseStore(releases: [
            makeRelease(name: "old", version: 1, status: .superseded),
            makeRelease(name: "active", version: 2, status: .deployed),
        ])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            let state = sut.viewState.value
            XCTAssertEqual(state?.releases.count, 1)
            XCTAssertEqual(state?.releases.first?.name, "active")
        }
    }

    func test_start_setsFailureWhenStoreFails() async {
        let store = SpyApplicationsReleaseStore(
            releases: [],
            error: HelmReleaseStoreError.unimplemented
        )

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            XCTAssertNotNil(sut.viewState.error)
            XCTAssertNil(sut.viewState.value)
        }
    }

    func test_start_emptyStoreProducesEmptyReleaseList() async {
        let store = SpyApplicationsReleaseStore(releases: [])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            let state = sut.viewState.value
            XCTAssertNotNil(state)
            XCTAssertEqual(state?.releases.count, 0)
        }
    }

    // MARK: - Sorting

    func test_applySort_nameDescending_reversesOrder() async {
        let store = SpyApplicationsReleaseStore(releases: [
            makeRelease(name: "alpha", version: 1),
            makeRelease(name: "zeta", version: 1),
        ])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            await sut.applySort(.nameDescending, clusterId: testClusterId)
            let names = sut.viewState.value?.releases.map(\.name)
            XCTAssertEqual(names?.first, "zeta")
            XCTAssertEqual(names?.last, "alpha")
        }
    }

    func test_applySort_updatedDescending_sortsByTimestampDescending() async {
        let store = SpyApplicationsReleaseStore(releases: [
            makeRelease(name: "early", version: 1, modifiedAt: "2026-01-01T00:00:00Z"),
            makeRelease(name: "recent", version: 1, modifiedAt: "2026-06-01T00:00:00Z"),
        ])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            await sut.applySort(.updatedDescending, clusterId: testClusterId)
            let names = sut.viewState.value?.releases.map(\.name)
            XCTAssertEqual(names?.first, "recent", "most recently updated appears first")
        }
    }

    // MARK: - Row projection

    func test_applicationRow_stripsRepositoryPrefixFromChartName() async {
        let store = SpyApplicationsReleaseStore(releases: [
            makeRelease(name: "app", version: 1, chartName: "ingress-nginx/nginx-ingress"),
        ])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            let row = sut.viewState.value?.releases.first
            XCTAssertEqual(row?.chartName, "nginx-ingress")
        }
    }

    // MARK: - openHelmDetail

    func test_openHelmDetail_callsOpenTabsWithHelmReleaseTab() async {
        let spy = SpyOpenTabsPort()
        let store = SpyApplicationsReleaseStore(releases: [
            makeRelease(name: "prometheus", version: 2),
        ])

        await withDependencies {
            $0.helmReleaseStore = store
            $0.openTabs = spy
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            guard let row = sut.viewState.value?.releases.first else {
                XCTFail("Expected at least one row")
                return
            }
            await sut.openHelmDetail(row: row, clusterId: testClusterId)
            XCTAssertEqual(spy.openedTabs.count, 1)
            if case .helmRelease(_, let name, let ns) = spy.openedTabs.first {
                XCTAssertEqual(name, "prometheus")
                XCTAssertEqual(ns, "default")
            } else {
                XCTFail("Expected helmRelease tab kind")
            }
        }
    }

    // MARK: - Extension hook flags

    func test_viewState_argocdAndFluxFlagsAreFalseInV1() async {
        let store = SpyApplicationsReleaseStore(releases: [makeRelease(name: "x", version: 1)])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = ApplicationsViewModel()
            await sut.start(clusterId: testClusterId)
            let state = sut.viewState.value
            XCTAssertFalse(state?.argocdEnabled ?? true, "argocdEnabled must be false in v1")
            XCTAssertFalse(state?.fluxEnabled ?? true, "fluxEnabled must be false in v1")
        }
    }
}

// MARK: - Helpers

private let testClusterId = ClusterId("adr-0067-test-cluster")

private func makeRelease(
    name: String,
    version: Int,
    status: ReleaseStatus = .deployed,
    chartName: String = "test-chart",
    modifiedAt: String = "2026-05-01T12:00:00Z"
) -> Release {
    Release(
        id: UUID(),
        kubernetesContextId: UUID(),
        name: name,
        namespace: "default",
        version: version,
        status: status,
        chart: ChartMetadata(
            name: chartName,
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
            lastDeployed: modifiedAt,
            deleted: nil,
            description: "Install complete",
            status: status,
            notes: ""
        ),
        manifestYAML: "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: test",
        valuesJSON: "{}",
        hooks: [],
        modifiedAtRFC3339: modifiedAt,
        sourceSecretName: "sh.helm.release.v1.\(name).v\(version)"
    )
}

// MARK: - Spy doubles

private final class SpyApplicationsReleaseStore: HelmReleaseStorePort, @unchecked Sendable {
    private let stubbedReleases: [Release]
    private let stubbedError: Error?

    init(releases: [Release], error: Error? = nil) {
        self.stubbedReleases = releases
        self.stubbedError = error
    }

    func listReleases(clusterId: ClusterId, namespace: String?) async throws -> [Release] {
        if let err = stubbedError { throw err }
        guard let ns = namespace else { return stubbedReleases }
        return stubbedReleases.filter { $0.namespace == ns }
    }

    func readRelease(secretName: String, namespace: String, clusterId: ClusterId) async throws -> Release {
        throw HelmReleaseStoreError.unimplemented
    }

    func writeRelease(_ release: Release, clusterId: ClusterId) async throws {
        throw HelmReleaseStoreError.unimplemented
    }
}

@MainActor
private final class SpyOpenTabsPort: OpenTabsPort, @unchecked Sendable {
    private(set) var openedTabs: [DocumentTab] = []

    func openTab(_ tab: DocumentTab) async {
        openedTabs.append(tab)
    }
}
