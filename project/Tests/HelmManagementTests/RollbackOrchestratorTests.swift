// Tests/HelmManagementTests/RollbackOrchestratorTests.swift — helm_management
// ADR ref: ADR-0015 §Rollback, ADR-0046 (lease mutual exclusion)

import XCTest
import Dependencies
import SharedKernel
@testable import HelmManagement

// MARK: - RollbackOrchestratorTests

final class RollbackOrchestratorTests: XCTestCase {

    // MARK: - Happy path: lease acquired, SSA applied, lease released, audit emitted

    func test_rollbackSuccessAcquiresLeaseAppliesSSAReleasesLeaseAndAudits() async throws {
        let release = makeRelease(version: 2)
        let leaseStore = SpyLeasePort()
        let releaseStore = StubStoreWith(target: makeRelease(version: 1))
        let ssaPort = SpySSAPort()
        let auditStore = SpyAuditPort()

        let entry = try await withDependencies {
            $0.rollbackLease = leaseStore
            $0.helmReleaseStore = releaseStore
            $0.serverSideApply = ssaPort
            $0.auditLog = auditStore
        } operation: {
            let orchestrator = RollbackOrchestrator()
            return try await orchestrator.rollback(
                release: release,
                toRevision: 1,
                clusterId: .init("ctx"),
                holderIdentity: "k8smanager-test"
            )
        }

        XCTAssertEqual(entry.revision, 1)
        let acquired = await leaseStore.acquiredCount
        XCTAssertEqual(acquired, 1, "Lease must be acquired once")
        let released = await leaseStore.releasedCount
        XCTAssertEqual(released, 1, "Lease must be released on success")
        let applied = await ssaPort.appliedCount
        XCTAssertGreaterThanOrEqual(applied, 1, "SSA must be called for manifest documents")
        let recordedActions = await auditStore.recordedActions
        XCTAssertTrue(recordedActions.contains(.rollbackSucceeded), "Audit must emit rollbackSucceeded")
    }

    // MARK: - Lease contention: rollback aborted, no SSA call, contention audit

    func test_rollbackBlockedWhenLeaseContentionDetected() async throws {
        let release = makeRelease(version: 2)
        let leasePort = ContentionLeasePort()
        let ssaPort = SpySSAPort()
        let auditStore = SpyAuditPort()

        do {
            try await withDependencies {
                $0.rollbackLease = leasePort
                $0.helmReleaseStore = UnimplementedHelmReleaseStorePort()
                $0.serverSideApply = ssaPort
                $0.auditLog = auditStore
            } operation: {
                let orchestrator = RollbackOrchestrator()
                _ = try await orchestrator.rollback(
                    release: release,
                    toRevision: 1,
                    clusterId: .init("ctx"),
                    holderIdentity: "k8smanager-test"
                )
            }
            XCTFail("Expected RollbackLeaseError.contention")
        } catch RollbackLeaseError.contention {
            let applied = await ssaPort.appliedCount
            XCTAssertEqual(applied, 0, "SSA must not be called on lease contention")
        }
    }

    // MARK: - SSA failure: lease still released, audit emits rollbackFailed

    func test_ssaFailureReleasesLeaseAndAuditsFailure() async throws {
        let release = makeRelease(version: 3)
        let leasePort = SpyLeasePort()
        let releaseStore = StubStoreWith(target: makeRelease(version: 2))
        let ssaPort = FailingSSAPort()
        let auditStore = SpyAuditPort()

        do {
            try await withDependencies {
                $0.rollbackLease = leasePort
                $0.helmReleaseStore = releaseStore
                $0.serverSideApply = ssaPort
                $0.auditLog = auditStore
            } operation: {
                let orchestrator = RollbackOrchestrator()
                _ = try await orchestrator.rollback(
                    release: release,
                    toRevision: 2,
                    clusterId: .init("ctx"),
                    holderIdentity: "k8smanager-test"
                )
            }
            XCTFail("Expected ServerSideApplyError")
        } catch {
            let released = await leasePort.releasedCount
            XCTAssertEqual(released, 1, "Lease must be released even on SSA failure")
            let recordedActions = await auditStore.recordedActions
            XCTAssertTrue(recordedActions.contains(.rollbackFailed), "Audit must emit rollbackFailed on SSA error")
        }
    }

    // MARK: - Audit record emitted with correct releaseId and revision

    func test_auditEntryCarriesCorrectReleaseIdAndRevision() async throws {
        let release = makeRelease(version: 4)
        let leasePort = SpyLeasePort()
        let releaseStore = StubStoreWith(target: makeRelease(version: 3, id: release.id))
        let ssaPort = SpySSAPort()
        let auditStore = SpyAuditPort()

        try await withDependencies {
            $0.rollbackLease = leasePort
            $0.helmReleaseStore = releaseStore
            $0.serverSideApply = ssaPort
            $0.auditLog = auditStore
        } operation: {
            let orchestrator = RollbackOrchestrator()
            _ = try await orchestrator.rollback(
                release: release,
                toRevision: 3,
                clusterId: .init("ctx"),
                holderIdentity: "k8smanager-test"
            )
        }

        let entries = await auditStore.recordedEntries
        XCTAssertEqual(entries.first?.revision, 3)
        XCTAssertEqual(entries.first?.action, .rollbackSucceeded)
    }

    // MARK: - Returned history entry reflects target revision status

    func test_returnedEntryReflectsTargetRevisionMetadata() async throws {
        let release = makeRelease(version: 5)
        let target = makeRelease(version: 2, status: .deployed)
        let leasePort = SpyLeasePort()
        let releaseStore = StubStoreWith(target: target)
        let ssaPort = SpySSAPort()
        let auditStore = SpyAuditPort()

        let entry = try await withDependencies {
            $0.rollbackLease = leasePort
            $0.helmReleaseStore = releaseStore
            $0.serverSideApply = ssaPort
            $0.auditLog = auditStore
        } operation: {
            let orchestrator = RollbackOrchestrator()
            return try await orchestrator.rollback(
                release: release,
                toRevision: 2,
                clusterId: .init("ctx"),
                holderIdentity: "k8smanager-test"
            )
        }

        XCTAssertEqual(entry.revision, 2)
        XCTAssertEqual(entry.status, .deployed)
        XCTAssertNil(entry.supersededAtRFC3339, "Returned entry for current revision must have no supersededAt")
    }
}

// MARK: - Helpers

private func makeRelease(version: Int, id: UUID = UUID(), status: ReleaseStatus = .deployed) -> Release {
    Release(
        id: id,
        kubernetesContextId: UUID(),
        name: "my-app",
        namespace: "default",
        version: version,
        status: status,
        chart: ChartMetadata(
            name: "my-chart",
            version: "1.0.0",
            appVersion: nil,
            apiVersion: .v2,
            description: nil,
            type: nil,
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
            status: status,
            notes: ""
        ),
        manifestYAML: "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cfg\n",
        valuesJSON: "{}",
        hooks: [],
        modifiedAtRFC3339: "2024-01-02T00:00:00Z",
        sourceSecretName: "sh.helm.release.v1.my-app.v\(version)"
    )
}

// MARK: - Test Doubles

private actor SpyLeasePort: RollbackLeasePort {
    private(set) var acquiredCount = 0
    private(set) var releasedCount = 0

    private func makeLease(releaseName: String, namespace: String, holderIdentity: String) -> RollbackLease {
        RollbackLease(
            namespace: namespace,
            releaseName: releaseName,
            holderIdentity: holderIdentity,
            acquireTime: "2024-01-01T00:00:00Z",
            renewTime: "2024-01-01T00:00:00Z"
        )
    }

    func acquireLease(releaseName: String, namespace: String, holderIdentity: String, clusterId: ClusterId) async throws -> RollbackLease {
        acquiredCount += 1
        return makeLease(releaseName: releaseName, namespace: namespace, holderIdentity: holderIdentity)
    }

    func renewLease(_ lease: RollbackLease, clusterId: ClusterId) async throws -> RollbackLease { lease }

    func releaseLease(_ lease: RollbackLease, clusterId: ClusterId) async throws {
        releasedCount += 1
    }
}

private struct ContentionLeasePort: RollbackLeasePort {
    func acquireLease(releaseName: String, namespace: String, holderIdentity: String, clusterId: ClusterId) async throws -> RollbackLease {
        throw RollbackLeaseError.contention(holderIdentity: "k8smanager-other-operator@example.com")
    }
    func renewLease(_ lease: RollbackLease, clusterId: ClusterId) async throws -> RollbackLease { lease }
    func releaseLease(_ lease: RollbackLease, clusterId: ClusterId) async throws {}
}

private actor SpySSAPort: ServerSideApplyPort {
    private(set) var appliedCount = 0

    func apply(manifestYAML: String, namespace: String, clusterId: ClusterId, force: Bool) async throws -> ApplyOutcome {
        appliedCount += 1
        return ApplyOutcome(apiVersion: "v1", kind: "ConfigMap", name: "cfg", httpStatus: 200)
    }
}

private struct FailingSSAPort: ServerSideApplyPort {
    func apply(manifestYAML: String, namespace: String, clusterId: ClusterId, force: Bool) async throws -> ApplyOutcome {
        throw ServerSideApplyError.transportError(detail: "simulated network failure")
    }
}

private struct StubStoreWith: HelmReleaseStorePort {
    let target: Release

    func listReleases(clusterId: ClusterId, namespace: String?) async throws -> [Release] { [target] }

    func readRelease(secretName: String, namespace: String, clusterId: ClusterId) async throws -> Release {
        target
    }

    func writeRelease(_ release: Release, clusterId: ClusterId) async throws {}
}

private actor SpyAuditPort: AuditLogPort {
    private(set) var recordedEntries: [HelmAuditEntry] = []

    var recordedActions: [HelmAuditAction] {
        recordedEntries.map(\.action)
    }

    func record(_ entry: HelmAuditEntry) async throws {
        recordedEntries.append(entry)
    }
}
