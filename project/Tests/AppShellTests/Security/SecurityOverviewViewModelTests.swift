// Tests/AppShellTests/Security/SecurityOverviewViewModelTests.swift
// Coverage: SecurityOverviewViewModel scoring heuristic + risk detection.

import XCTest
@testable import AppShell
import SharedKernel

// MARK: - SecurityOverviewViewModelTests

@MainActor
final class SecurityOverviewViewModelTests: XCTestCase {

    // MARK: - Empty cluster → score 100

    func test_emptyCluster_scoreIsMaximum() async {
        let sut = makeSUT(snapshot: .init())
        await sut.start(clusterId: ClusterId("test-cluster"))
        XCTAssertEqual(sut.score, 100)
    }

    func test_emptyCluster_findingsAreZero() async {
        let sut = makeSUT(snapshot: .init())
        await sut.start(clusterId: ClusterId("test-cluster"))
        let f = sut.findings
        XCTAssertEqual(f.critical + f.high + f.medium + f.low, 0)
    }

    // MARK: - 1 privileged pod → score 90

    func test_onePrivilegedPod_scoreIs90() async {
        let snapshot = SecuritySnapshot(privilegedPodCount: 1)
        let sut = makeSUT(snapshot: snapshot)
        await sut.start(clusterId: ClusterId("test-cluster"))
        XCTAssertEqual(sut.score, 90) // 100 - 10
    }

    // MARK: - Multiple risks → cumulative deduction

    func test_multipleRisks_deductionsAreAdditive() async {
        let snapshot = SecuritySnapshot(
            privilegedPodCount: 1,          // -10
            rootPodCount: 2,                // -10
            clusterAdminBindingCount: 1,    // -15
            wildcardRoleCount: 2,           // -6
            exposedLoadBalancerCount: 1     // -8
        )
        let sut = makeSUT(snapshot: snapshot)
        await sut.start(clusterId: ClusterId("test-cluster"))
        // Expected: 100 - 10 - 10 - 15 - 6 - 8 = 51
        XCTAssertEqual(sut.score, 51)
    }

    // MARK: - Score floor at 0

    func test_extremeRisks_scoreFloorAtZero() async {
        let snapshot = SecuritySnapshot(
            privilegedPodCount: 10,         // -100 alone hits floor
            clusterAdminBindingCount: 5
        )
        let sut = makeSUT(snapshot: snapshot)
        await sut.start(clusterId: ClusterId("test-cluster"))
        XCTAssertEqual(sut.score, 0)
        XCTAssertGreaterThanOrEqual(sut.score, 0)
    }

    // MARK: - Error path graceful

    func test_portError_loadStateIsFailure() async {
        let sut = SecurityOverviewViewModel()
        sut.listPort = AlwaysFailingPort()
        await sut.start(clusterId: ClusterId("test-cluster"))
        guard case .failure = sut.loadState else {
            XCTFail("Expected .failure load state")
            return
        }
        // Score should remain at the initial default (not 0) on error.
        XCTAssertEqual(sut.score, 100)
    }

    // MARK: - computeScore unit tests (internal visibility)

    func test_computeScore_wildcardOnly_deductsCorrectly() {
        let sut = SecurityOverviewViewModel()
        let snapshot = SecuritySnapshot(wildcardRoleCount: 3) // -9
        let result = sut.computeScore(snapshot: snapshot)
        XCTAssertEqual(result, 91)
    }

    func test_computeScore_clusterAdminBinding_deductsCorrectly() {
        let sut = SecurityOverviewViewModel()
        let snapshot = SecuritySnapshot(clusterAdminBindingCount: 2) // -30
        let result = sut.computeScore(snapshot: snapshot)
        XCTAssertEqual(result, 70)
    }
}

// MARK: - Test helpers

private func makeSUT(snapshot: SecuritySnapshot) -> SecurityOverviewViewModel {
    let sut = SecurityOverviewViewModel()
    sut.listPort = StubSecurityListPort(snapshot: snapshot)
    return sut
}

// MARK: - Test doubles

private struct StubSecurityListPort: KubernetesSecurityListPort {
    let snapshot: SecuritySnapshot

    func fetchSecuritySnapshot(clusterId: ClusterId) async throws -> SecuritySnapshot {
        snapshot
    }
}

private struct AlwaysFailingPort: KubernetesSecurityListPort {
    func fetchSecuritySnapshot(clusterId: ClusterId) async throws -> SecuritySnapshot {
        throw SecurityTestError.simulatedFailure
    }
}

private enum SecurityTestError: Error {
    case simulatedFailure
}
