// Tests/AppShellTests/Helm/HelmReleasesViewModelTests.swift
// Coverage: HelmReleasesViewModel — load, rollback, uninstall, error paths.
// ADR ref: ADR-0015 (Helm native phased), ADR-0046 (rollback lease mutex)

import XCTest
import Dependencies
@testable import AppShell
import HelmManagement
import SharedKernel

// MARK: - HelmReleasesViewModelTests

@MainActor
final class HelmReleasesViewModelTests: XCTestCase {

    // MARK: start / load

    func test_start_setsSuccessWithDeduplicatedRows() async {
        // Two revisions of the same release; only the latest should appear as one row.
        let nginx3 = makeRelease(name: "nginx", version: 3)
        let nginx2 = makeRelease(name: "nginx", version: 2)
        let store = SpyHelmReleaseStore(releases: [nginx3, nginx2])

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = HelmReleasesViewModel()
            await sut.start(clusterId: testClusterId)
            let rows = sut.releases.value
            XCTAssertEqual(rows?.count, 1, "two revisions of same release collapse to one row")
            XCTAssertEqual(rows?.first?.revision, 3, "latest revision wins")
        }
    }

    func test_start_setsFailureWhenStoreFails() async {
        let store = SpyHelmReleaseStore(error: HelmReleaseStoreError.unimplemented)

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = HelmReleasesViewModel()
            await sut.start(clusterId: testClusterId)
            XCTAssertNotNil(sut.releases.error)
            XCTAssertNil(sut.releases.value)
        }
    }

    // MARK: filteredRows

    func test_filteredRows_matchesSearchText() async {
        let releases = [
            makeRelease(name: "nginx", version: 1),
            makeRelease(name: "cert-manager", version: 1),
        ]
        let store = SpyHelmReleaseStore(releases: releases)

        await withDependencies {
            $0.helmReleaseStore = store
        } operation: {
            let sut = HelmReleasesViewModel()
            await sut.start(clusterId: testClusterId)
            sut.searchText = "cert"
            XCTAssertEqual(sut.filteredRows.count, 1)
            XCTAssertEqual(sut.filteredRows.first?.name, "cert-manager")
        }
    }

    // MARK: rollback

    func test_rollback_acquiresLeaseWhenStoreHasRelease() async {
        let release = makeRelease(name: "prometheus", version: 5)
        let store = SpyHelmReleaseStore(releases: [release])
        let lease = SpyRollbackLeasePort()

        await withDependencies {
            $0.helmReleaseStore = store
            $0.rollbackLease = lease
        } operation: {
            let sut = HelmReleasesViewModel()
            let ref = ReleaseRef(name: "prometheus", namespace: "default")
            await sut.rollback(release: ref, toRevision: 4, clusterId: testClusterId)
            XCTAssertTrue(lease.acquireCalled, "lease must be acquired before rollback")
            XCTAssertFalse(sut.rollbackInProgress, "inProgress resets on completion")
        }
    }

    func test_rollback_setsErrorWhenLeaseContended() async {
        let store = SpyHelmReleaseStore(releases: [])
        let lease = SpyRollbackLeasePort(acquireError: RollbackLeaseError.contention(holderIdentity: "other-instance"))

        await withDependencies {
            $0.helmReleaseStore = store
            $0.rollbackLease = lease
        } operation: {
            let sut = HelmReleasesViewModel()
            let ref = ReleaseRef(name: "grafana", namespace: "monitoring")
            await sut.rollback(release: ref, toRevision: 2, clusterId: testClusterId)
            XCTAssertNotNil(sut.rollbackError)
            XCTAssertFalse(sut.rollbackInProgress)
        }
    }

    func test_rollback_failsWhenLeasePortUnimplemented() async {
        let store = SpyHelmReleaseStore(releases: [])

        await withDependencies {
            $0.helmReleaseStore = store
            $0.rollbackLease = UnimplementedRollbackLeasePort()
        } operation: {
            let sut = HelmReleasesViewModel()
            let ref = ReleaseRef(name: "vault", namespace: "default")
            await sut.rollback(release: ref, toRevision: 1, clusterId: testClusterId)
            XCTAssertNotNil(sut.rollbackError)
            XCTAssertFalse(sut.rollbackInProgress)
        }
    }

    // MARK: uninstall

    func test_uninstall_setsPhase2Error() async {
        let sut = HelmReleasesViewModel()
        let ref = ReleaseRef(name: "loki", namespace: "logging")
        await sut.uninstall(release: ref, clusterId: testClusterId)
        XCTAssertNotNil(sut.rollbackError)
        let err = sut.rollbackError as? HelmReleasesViewModelError
        XCTAssertEqual(err, .uninstallNotImplemented)
    }
}

// MARK: - Test helpers

private let testClusterId = ClusterId("test-cluster-123")

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
            lastDeployed: "2026-01-0\(min(version, 9))T00:00:00Z",
            deleted: nil,
            description: "Install complete",
            status: .deployed,
            notes: ""
        ),
        manifestYAML: "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: test",
        valuesJSON: "{}",
        hooks: [],
        modifiedAtRFC3339: "2026-01-0\(min(version, 9))T00:00:00Z",
        sourceSecretName: "sh.helm.release.v1.\(name).v\(version)"
    )
}

// MARK: - Spy doubles

private final class SpyHelmReleaseStore: HelmReleaseStorePort, @unchecked Sendable {
    let stubbedReleases: [Release]
    let stubbedError: Error?

    init(releases: [Release], error: Error? = nil) {
        self.stubbedReleases = releases
        self.stubbedError = error
    }

    func listReleases(clusterId: ClusterId, namespace: String?) async throws -> [Release] {
        if let e = stubbedError { throw e }
        if let ns = namespace {
            return stubbedReleases.filter { $0.namespace == ns }
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

private final class SpyRollbackLeasePort: RollbackLeasePort, @unchecked Sendable {
    private(set) var acquireCalled: Bool = false
    private(set) var releaseCalled: Bool = false
    let acquireError: Error?

    init(acquireError: Error? = nil) {
        self.acquireError = acquireError
    }

    func acquireLease(
        releaseName: String,
        namespace: String,
        holderIdentity: String,
        clusterId: ClusterId
    ) async throws -> RollbackLease {
        acquireCalled = true
        if let e = acquireError { throw e }
        return RollbackLease(
            namespace: namespace,
            releaseName: releaseName,
            holderIdentity: holderIdentity,
            acquireTime: "2026-01-01T00:00:00Z",
            renewTime: "2026-01-01T00:00:00Z"
        )
    }

    func renewLease(_ lease: RollbackLease, clusterId: ClusterId) async throws -> RollbackLease {
        lease
    }

    func releaseLease(_ lease: RollbackLease, clusterId: ClusterId) async throws {
        releaseCalled = true
    }
}

// MARK: - Equatable conformance for assertion

extension HelmReleasesViewModelError: Equatable {
    public static func == (lhs: HelmReleasesViewModelError, rhs: HelmReleasesViewModelError) -> Bool {
        switch (lhs, rhs) {
        case (.uninstallNotImplemented, .uninstallNotImplemented): return true
        }
    }
}
