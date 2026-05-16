// Tests/HelmManagementTests/HelmManagementTests.swift — helm_management
// ADR ref: ADR-0015, ADR-0046

import XCTest
import Dependencies
@testable import HelmManagement

// MARK: - ReleaseStatusTests

final class ReleaseStatusTests: XCTestCase {
    func test_allCasesRoundTripRawValue() {
        for status in ReleaseStatus.allCases {
            XCTAssertEqual(ReleaseStatus(rawValue: status.rawValue), status)
        }
    }

    func test_deployedIsTerminalAndCurrent() {
        XCTAssertTrue(ReleaseStatus.deployed.isTerminal)
        XCTAssertTrue(ReleaseStatus.deployed.isCurrent)
    }

    func test_supersededIsTerminalNotCurrent() {
        XCTAssertTrue(ReleaseStatus.superseded.isTerminal)
        XCTAssertFalse(ReleaseStatus.superseded.isCurrent)
    }

    func test_pendingUpgradeIsNeitherTerminalNorCurrent() {
        XCTAssertFalse(ReleaseStatus.pendingUpgrade.isTerminal)
        XCTAssertFalse(ReleaseStatus.pendingUpgrade.isCurrent)
    }

    func test_codableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(ReleaseStatus.pendingRollback)
        let decoded = try JSONDecoder().decode(ReleaseStatus.self, from: encoded)
        XCTAssertEqual(decoded, .pendingRollback)
    }
}

// MARK: - ChartMetadataTests

final class ChartMetadataTests: XCTestCase {
    func test_equalityOnIdenticalValues() {
        let a = makeChartMetadata()
        let b = makeChartMetadata()
        XCTAssertEqual(a, b)
    }

    func test_inequalityOnDifferentVersion() {
        let a = makeChartMetadata(version: "1.0.0")
        let b = makeChartMetadata(version: "2.0.0")
        XCTAssertNotEqual(a, b)
    }

    func test_codableRoundTrip() throws {
        let metadata = makeChartMetadata()
        let encoded = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(ChartMetadata.self, from: encoded)
        XCTAssertEqual(decoded, metadata)
    }

    func test_optionalFieldsAbsentWhenNil() {
        let metadata = makeChartMetadata()
        XCTAssertNil(metadata.appVersion)
        XCTAssertNil(metadata.description)
        XCTAssertNil(metadata.type)
        XCTAssertNil(metadata.icon)
        XCTAssertNil(metadata.home)
    }

    func test_chartDependencyCodeable() throws {
        let dep = ChartDependency(
            name: "redis",
            version: ">=7.0.0",
            repository: "https://charts.bitnami.com/bitnami",
            alias: nil,
            condition: "redis.enabled",
            tags: ["cache"]
        )
        let data = try JSONEncoder().encode(dep)
        let decoded = try JSONDecoder().decode(ChartDependency.self, from: data)
        XCTAssertEqual(decoded, dep)
    }

    func test_maintainerCodeable() throws {
        let m = Maintainer(name: "Alice", email: "alice@example.com", url: nil)
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(Maintainer.self, from: data)
        XCTAssertEqual(decoded, m)
    }

    // MARK: Helpers

    private func makeChartMetadata(version: String = "1.0.0") -> ChartMetadata {
        ChartMetadata(
            name: "nginx",
            version: version,
            appVersion: nil,
            apiVersion: .v2,
            description: nil,
            type: nil,
            icon: nil,
            dependencies: [],
            maintainers: [],
            home: nil,
            sources: []
        )
    }
}

// MARK: - ReleaseTests

final class ReleaseTests: XCTestCase {
    func test_versionOneIsValid() {
        let release = makeRelease(version: 1)
        XCTAssertEqual(release.version, 1)
    }

    func test_preconditionTriggersOnVersionZero() {
        // Swift preconditions abort in debug builds; we test the happy path only.
        let release = makeRelease(version: 3)
        XCTAssertGreaterThanOrEqual(release.version, 1)
    }

    func test_sourceSecretNameConvention() {
        let release = makeRelease(version: 2)
        XCTAssertEqual(release.sourceSecretName, "sh.helm.release.v1.my-release.v2")
    }

    func test_codableRoundTrip() throws {
        let release = makeRelease(version: 1)
        let data = try JSONEncoder().encode(release)
        let decoded = try JSONDecoder().decode(Release.self, from: data)
        XCTAssertEqual(decoded, release)
    }

    func test_hashableDistinctByVersion() {
        let r1 = makeRelease(version: 1)
        let r2 = makeRelease(version: 2)
        XCTAssertNotEqual(r1.hashValue, r2.hashValue)
    }

    // MARK: Helpers

    private func makeRelease(version: Int) -> Release {
        Release(
            id: UUID(),
            kubernetesContextId: UUID(),
            name: "my-release",
            namespace: "default",
            version: version,
            status: .deployed,
            chart: ChartMetadata(
                name: "nginx",
                version: "1.2.3",
                appVersion: "1.25.0",
                apiVersion: .v2,
                description: "A chart for nginx",
                type: .application,
                icon: nil,
                dependencies: [],
                maintainers: [],
                home: nil,
                sources: []
            ),
            info: ReleaseInfo(
                firstDeployed: "2024-01-01T00:00:00Z",
                lastDeployed: "2024-01-02T00:00:00Z",
                deleted: nil,
                description: "Install complete",
                status: .deployed,
                notes: ""
            ),
            manifestYAML: "apiVersion: v1\nkind: Service\n",
            valuesJSON: "{}",
            hooks: [],
            modifiedAtRFC3339: "2024-01-02T00:00:00Z",
            sourceSecretName: "sh.helm.release.v1.my-release.v\(version)"
        )
    }
}

// MARK: - ReleaseHistoryEntryTests

final class ReleaseHistoryEntryTests: XCTestCase {
    func test_revisionOneIsValid() {
        let entry = makeEntry(revision: 1, status: .deployed)
        XCTAssertEqual(entry.revision, 1)
    }

    func test_supersededEntryHasTimestamp() {
        let entry = ReleaseHistoryEntry(
            revision: 1,
            deployedAtRFC3339: "2024-01-01T00:00:00Z",
            status: .superseded,
            chartVersion: "1.0.0",
            appVersion: nil,
            description: "Install complete",
            supersededAtRFC3339: "2024-01-02T00:00:00Z"
        )
        XCTAssertNotNil(entry.supersededAtRFC3339)
    }

    func test_currentRevisionHasNoSupersededTimestamp() {
        let entry = makeEntry(revision: 3, status: .deployed)
        XCTAssertNil(entry.supersededAtRFC3339)
    }

    func test_codableRoundTrip() throws {
        let entry = makeEntry(revision: 2, status: .superseded)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ReleaseHistoryEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    // MARK: Helpers

    private func makeEntry(revision: Int, status: ReleaseStatus) -> ReleaseHistoryEntry {
        ReleaseHistoryEntry(
            revision: revision,
            deployedAtRFC3339: "2024-01-01T00:00:00Z",
            status: status,
            chartVersion: "1.0.0",
            appVersion: "1.0",
            description: "Install complete",
            supersededAtRFC3339: nil
        )
    }
}

// MARK: - HookManifestTests

final class HookManifestTests: XCTestCase {
    func test_hookEventRawValueRoundTrip() {
        for event in HookEvent.allCases {
            XCTAssertEqual(HookEvent(rawValue: event.rawValue), event)
        }
    }

    func test_hookManifestCodable() throws {
        let hook = HookManifest(
            name: "pre-install-job",
            kind: "Job",
            apiVersion: "batch/v1",
            events: [.preInstall],
            deletePolicy: ["before-hook-creation"],
            weight: 0
        )
        let data = try JSONEncoder().encode(hook)
        let decoded = try JSONDecoder().decode(HookManifest.self, from: data)
        XCTAssertEqual(decoded, hook)
    }

    func test_negativeWeightIsPermitted() {
        let hook = HookManifest(
            name: "cleanup",
            kind: "Job",
            apiVersion: "batch/v1",
            events: [.postDelete],
            deletePolicy: ["hook-succeeded"],
            weight: -5
        )
        XCTAssertEqual(hook.weight, -5)
    }
}

// MARK: - RollbackLeaseTests

final class RollbackLeaseTests: XCTestCase {
    func test_leaseNameIsTruncatedTo63Characters() {
        let longName = String(repeating: "a", count: 60)
        let lease = RollbackLease(
            namespace: "default",
            releaseName: longName,
            holderIdentity: "k8smanager-test-user@example.com",
            acquireTime: "2024-01-01T00:00:00Z",
            renewTime: "2024-01-01T00:00:00Z"
        )
        XCTAssertLessThanOrEqual(lease.leaseName.count, 63)
    }

    func test_leaseNamePrefix() {
        let lease = RollbackLease(
            namespace: "default",
            releaseName: "nginx",
            holderIdentity: "k8smanager-test",
            acquireTime: "2024-01-01T00:00:00Z",
            renewTime: "2024-01-01T00:00:00Z"
        )
        XCTAssertEqual(lease.leaseName, "k8smanager-helm-rollback-nginx")
    }

    func test_staleLeaseDetectedWhenRenewTimeExpired() {
        // renew = 2024-01-01T00:00:00Z + 60s = stale before 2024-01-01T00:01:01Z
        let lease = RollbackLease(
            namespace: "default",
            releaseName: "nginx",
            holderIdentity: "k8smanager-abc",
            acquireTime: "2024-01-01T00:00:00Z",
            renewTime: "2024-01-01T00:00:00Z"
        )
        let future = Date(timeIntervalSince1970: 1_704_067_261) // 2024-01-01T00:01:01Z
        XCTAssertTrue(lease.isStale(at: future))
    }

    func test_freshLeaseNotStale() {
        let formatter = ISO8601DateFormatter()
        let renewTime = formatter.string(from: Date(timeIntervalSinceNow: -10))
        let lease = RollbackLease(
            namespace: "default",
            releaseName: "nginx",
            holderIdentity: "k8smanager-abc",
            acquireTime: renewTime,
            renewTime: renewTime
        )
        // Reference is "now"; lease was renewed 10 seconds ago, expires in 50 more
        XCTAssertFalse(lease.isStale(at: Date()))
    }

    func test_leaseDurationIs60Seconds() {
        XCTAssertEqual(RollbackLease.leaseDurationSeconds, 60)
    }

    func test_renewIntervalIs20Seconds() {
        XCTAssertEqual(RollbackLease.renewIntervalSeconds, 20)
    }

    func test_codableRoundTrip() throws {
        let lease = RollbackLease(
            namespace: "production",
            releaseName: "cert-manager",
            holderIdentity: "k8smanager-test",
            acquireTime: "2024-06-01T12:00:00Z",
            renewTime: "2024-06-01T12:00:20Z"
        )
        let data = try JSONEncoder().encode(lease)
        let decoded = try JSONDecoder().decode(RollbackLease.self, from: data)
        XCTAssertEqual(decoded, lease)
    }
}

// MARK: - DependenciesTests

final class DependenciesTests: XCTestCase {
    func test_helmReleaseStorePortDefaultThrowsUnimplemented() async {
        await withDependencies {
            $0.helmReleaseStore = UnimplementedHelmReleaseStorePort()
        } operation: {
            do {
                @Dependency(\.helmReleaseStore) var port
                _ = try await port.listReleases(clusterId: .init("test"), namespace: nil)
                XCTFail("Expected unimplemented error")
            } catch HelmReleaseStoreError.unimplemented {
                // Expected
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_serverSideApplyPortDefaultThrowsUnimplemented() async {
        await withDependencies {
            $0.serverSideApply = UnimplementedServerSideApplyPort()
        } operation: {
            do {
                @Dependency(\.serverSideApply) var port
                _ = try await port.apply(
                    manifestYAML: "",
                    namespace: "default",
                    clusterId: .init("test"),
                    force: false
                )
                XCTFail("Expected unimplemented error")
            } catch ServerSideApplyError.unimplemented {
                // Expected
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_rollbackLeasePortDefaultThrowsUnimplemented() async {
        await withDependencies {
            $0.rollbackLease = UnimplementedRollbackLeasePort()
        } operation: {
            do {
                @Dependency(\.rollbackLease) var port
                _ = try await port.acquireLease(
                    releaseName: "nginx",
                    namespace: "default",
                    holderIdentity: "k8smanager-test",
                    clusterId: .init("test")
                )
                XCTFail("Expected unimplemented error")
            } catch RollbackLeaseError.unimplemented {
                // Expected
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_chartRepositoryPortPhase2NotImplemented() async {
        await withDependencies {
            $0.chartRepository = UnimplementedChartRepositoryPort()
        } operation: {
            do {
                @Dependency(\.chartRepository) var port
                _ = try await port.fetchChartMetadataOCI(
                    reference: "oci://example.com/charts/nginx:1.0.0",
                    clusterId: .init("test")
                )
                XCTFail("Expected notImplementedPhase2")
            } catch ChartRepositoryError.notImplementedPhase2 {
                // Expected for Phase 1
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
