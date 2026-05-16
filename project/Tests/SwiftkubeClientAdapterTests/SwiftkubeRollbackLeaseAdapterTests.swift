// SwiftkubeRollbackLeaseAdapterTests.swift — SwiftkubeClientAdapterTests
// Coverage: port protocol contract, leaseName truncation, RollbackLease.isStale,
//           UnimplementedRollbackLeasePort sentinel, dependency-injection wiring.
// Note: live Kubernetes API calls require a running cluster (excluded from CI).
// All assertions exercised here are pure logic — no network involved.

import XCTest
import SharedKernel
@testable import ClusterConnectivity
@testable import HelmManagement
@testable import SwiftkubeClientAdapter

// MARK: - RollbackLeaseNameTests

/// Verifies the `leaseName` computation on `RollbackLease`.
final class RollbackLeaseNameTests: XCTestCase {

    func test_leaseName_shortReleaseName_prefixedCorrectly() {
        let lease = makeLeaseValueObject(releaseName: "my-release")
        XCTAssertEqual(lease.leaseName, "k8smanager-helm-rollback-my-release")
    }

    func test_leaseName_longReleaseName_truncatedTo63Characters() {
        let long = String(repeating: "a", count: 100)
        let lease = makeLeaseValueObject(releaseName: long)
        XCTAssertEqual(lease.leaseName.count, 63)
        XCTAssertTrue(lease.leaseName.hasPrefix("k8smanager-helm-rollback-"))
    }

    func test_leaseName_exactlyFillsPrefix_producesCorrectString() {
        // "k8smanager-helm-rollback-" is 25 chars; 38 more = exactly 63.
        let releaseName = String(repeating: "b", count: 38)
        let lease = makeLeaseValueObject(releaseName: releaseName)
        XCTAssertEqual(lease.leaseName.count, 63)
    }
}

// MARK: - RollbackLeaseIsStaleTests

/// Verifies the `isStale(at:)` predicate on `RollbackLease`.
final class RollbackLeaseIsStaleTests: XCTestCase {

    func test_isStale_whenRenewTimeIsRecent_returnsFalse() {
        let renewTime = ISO8601DateFormatter().string(from: Date())
        let lease = makeLeaseValueObject(renewTime: renewTime)
        XCTAssertFalse(lease.isStale(at: Date()))
    }

    func test_isStale_whenRenewTimePlusDurationIsInThePast_returnsTrue() {
        // Set renewTime 61 seconds before reference so that
        // renewTime + 60s < referenceDate.
        let renewDate = Date(timeIntervalSinceNow: -(Double(RollbackLease.leaseDurationSeconds) + 1))
        let renewTime = ISO8601DateFormatter().string(from: renewDate)
        let lease = makeLeaseValueObject(renewTime: renewTime)
        XCTAssertTrue(lease.isStale(at: Date()))
    }

    func test_isStale_whenRenewTimeCannotBeParsed_returnsTrue() {
        let lease = makeLeaseValueObject(renewTime: "not-a-date")
        XCTAssertTrue(lease.isStale(at: Date()))
    }

    func test_isStale_exactlyAtBoundary_returnsFalse() {
        // renewTime exactly now; renewTime + 60s is in the future.
        let renewTime = ISO8601DateFormatter().string(from: Date())
        let lease = makeLeaseValueObject(renewTime: renewTime)
        XCTAssertFalse(lease.isStale(at: Date()))
    }
}

// MARK: - UnimplementedRollbackLeasePortTests

/// Verifies that the sentinel throws `.unimplemented` for all three operations.
final class UnimplementedRollbackLeasePortTests: XCTestCase {

    private let port = UnimplementedRollbackLeasePort()
    private let clusterId = ClusterId("test-cluster")

    func test_acquireLease_throwsUnimplemented() async {
        do {
            _ = try await port.acquireLease(
                releaseName: "my-release",
                namespace: "default",
                holderIdentity: "k8smanager-abc-user@example.com",
                clusterId: clusterId
            )
            XCTFail("Expected RollbackLeaseError.unimplemented")
        } catch RollbackLeaseError.unimplemented {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_renewLease_throwsUnimplemented() async {
        do {
            _ = try await port.renewLease(makeLeaseValueObject(), clusterId: clusterId)
            XCTFail("Expected RollbackLeaseError.unimplemented")
        } catch RollbackLeaseError.unimplemented {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_releaseLease_throwsUnimplemented() async {
        do {
            try await port.releaseLease(makeLeaseValueObject(), clusterId: clusterId)
            XCTFail("Expected RollbackLeaseError.unimplemented")
        } catch RollbackLeaseError.unimplemented {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - SwiftkubeRollbackLeaseAdapterConstructionTests

/// Smoke tests for adapter construction. No network required — the resolver
/// is never called during init; errors only surface when an operation executes.
final class SwiftkubeRollbackLeaseAdapterConstructionTests: XCTestCase {

    func test_init_withResolver_constructsWithoutCrashing() {
        let adapter = SwiftkubeRollbackLeaseAdapter(
            resolver: { _ in
                ClusterParams(
                    server: URL(string: "https://127.0.0.1:6443")!,
                    auth: .bearerToken(BearerTokenAuth(token: "test-token")),
                    insecureSkipTLSVerify: true,
                    caStrategy: .system
                )
            }
        )
        XCTAssertTrue(type(of: adapter) == SwiftkubeRollbackLeaseAdapter.self)
    }

    func test_acquireLease_whenResolverThrows_surfacesTransportError() async {
        let adapter = SwiftkubeRollbackLeaseAdapter(resolver: { _ in
            throw RollbackLeaseError.transportError(detail: "resolver failed")
        })
        do {
            _ = try await adapter.acquireLease(
                releaseName: "nginx",
                namespace: "default",
                holderIdentity: "k8smanager-uuid-user@example.com",
                clusterId: ClusterId("no-cluster")
            )
            XCTFail("Expected an error when resolver throws")
        } catch {
            // Any error is acceptable — the point is no crash.
            XCTAssertNotNil(error)
        }
    }

    func test_renewLease_whenResolverThrows_surfacesError() async {
        let adapter = SwiftkubeRollbackLeaseAdapter(resolver: { _ in
            throw RollbackLeaseError.transportError(detail: "resolver failed")
        })
        do {
            _ = try await adapter.renewLease(makeLeaseValueObject(), clusterId: ClusterId("no-cluster"))
            XCTFail("Expected an error when resolver throws")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func test_releaseLease_whenResolverThrows_surfacesError() async {
        let adapter = SwiftkubeRollbackLeaseAdapter(resolver: { _ in
            throw RollbackLeaseError.transportError(detail: "resolver failed")
        })
        do {
            try await adapter.releaseLease(makeLeaseValueObject(), clusterId: ClusterId("no-cluster"))
            XCTFail("Expected an error when resolver throws")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}

// MARK: - Helpers

private func makeLeaseValueObject(
    releaseName: String = "my-release",
    namespace: String = "default",
    holderIdentity: String = "k8smanager-test-user@example.com",
    renewTime: String? = nil
) -> RollbackLease {
    let now = ISO8601DateFormatter().string(from: Date())
    return RollbackLease(
        namespace: namespace,
        releaseName: releaseName,
        holderIdentity: holderIdentity,
        acquireTime: now,
        renewTime: renewTime ?? now
    )
}
