// SwiftkubeClientAdapterTests.swift — SwiftkubeClientAdapter target
// XCTest coverage: construction smoke tests + response-to-state mapper.
// Note: integration tests that hit a real Kubernetes API server are excluded
// (no network in CI). The mapper function is package-internal (visible via
// @testable import) and covers all branching without network.

import XCTest
import SharedKernel
@testable import ClusterConnectivity
@testable import SwiftkubeClientAdapter

// MARK: - ConstructionTests

/// Verifies that `SwiftkubeApiAdapter` can be instantiated with various
/// resolver closures without crashing.
final class ConstructionTests: XCTestCase {

    func test_init_withBearerTokenResolver() {
        let adapter = SwiftkubeApiAdapter(
            resolver: { _ in
                ClusterParams(
                    server: URL(string: "https://127.0.0.1:6443")!,
                    auth: .bearerToken(BearerTokenAuth(token: "test-token")),
                    insecureSkipTLSVerify: true,
                    caStrategy: .system
                )
            }
        )
        // Construction succeeded — type check is the assertion.
        XCTAssertTrue(type(of: adapter) == SwiftkubeApiAdapter.self)
    }

    func test_init_withUnsupportedAuthThrowsAtCallTime() async {
        // The adapter itself initialises cleanly; the error fires inside probeHealth.
        let adapter = SwiftkubeApiAdapter(
            resolver: { _ in
                ClusterParams(
                    server: URL(string: "https://127.0.0.1:6443")!,
                    auth: .clientCert(ClientCertAuth(certPEM: "PEM", keyPEM: "KEY")),
                    insecureSkipTLSVerify: false,
                    caStrategy: .system
                )
            }
        )
        do {
            _ = try await adapter.probeHealth(clusterId: ClusterId("test"))
            XCTFail("Expected KubernetesApiError.transportError to be thrown")
        } catch KubernetesApiError.transportError(let detail) {
            XCTAssertTrue(detail.contains("not yet implemented"), "detail=\(detail)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_init_execPluginAuthThrowsAtCallTime() async {
        let adapter = SwiftkubeApiAdapter(
            resolver: { _ in
                ClusterParams(
                    server: URL(string: "https://127.0.0.1:6443")!,
                    auth: .execPlugin(ExecPluginAuth(
                        apiVersion: "client.authentication.k8s.io/v1",
                        command: "/usr/local/bin/aws"
                    )),
                    insecureSkipTLSVerify: false,
                    caStrategy: .system
                )
            }
        )
        do {
            _ = try await adapter.probeHealth(clusterId: ClusterId("test"))
            XCTFail("Expected KubernetesApiError.transportError to be thrown")
        } catch KubernetesApiError.transportError(let detail) {
            XCTAssertTrue(detail.contains("not yet implemented"), "detail=\(detail)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - StatusCodeMapperTests

/// Unit-tests `statusCodeToHealthState(_:)` — the pure HTTP-status-to-domain
/// mapping function. No network required.
final class StatusCodeMapperTests: XCTestCase {

    private let adapter = SwiftkubeApiAdapter(resolver: { _ in
        ClusterParams(
            server: URL(string: "https://127.0.0.1:6443")!,
            auth: .bearerToken(BearerTokenAuth(token: "tok")),
            insecureSkipTLSVerify: true,
            caStrategy: .system
        )
    })

    func test_200_isReachable() {
        XCTAssertEqual(adapter.statusCodeToHealthState(200), .reachable)
    }

    func test_201_isReachable() {
        XCTAssertEqual(adapter.statusCodeToHealthState(201), .reachable)
    }

    func test_301_isReachable() {
        XCTAssertEqual(adapter.statusCodeToHealthState(301), .reachable)
    }

    func test_401_isUnauthorized() {
        XCTAssertEqual(adapter.statusCodeToHealthState(401), .unauthorized)
    }

    func test_403_isForbidden() {
        XCTAssertEqual(adapter.statusCodeToHealthState(403), .forbidden)
    }

    func test_500_isDegraded() {
        XCTAssertEqual(adapter.statusCodeToHealthState(500), .degraded)
    }

    func test_503_isDegraded() {
        XCTAssertEqual(adapter.statusCodeToHealthState(503), .degraded)
    }

    func test_404_isUnreachable() {
        // 404 does not map to degraded or the auth states; falls to .unreachable.
        XCTAssertEqual(adapter.statusCodeToHealthState(404), .unreachable)
    }

    func test_0_isUnreachable() {
        XCTAssertEqual(adapter.statusCodeToHealthState(0), .unreachable)
    }
}

// MARK: - ResolverErrorTests

/// Verifies that errors thrown by the resolver are surfaced as
/// `HealthStatus.unreachable` (not re-thrown) from `probeHealth`.
final class ResolverErrorTests: XCTestCase {

    private enum FakeError: Error { case notFound }

    func test_probeHealth_whenResolverThrows_returnsUnreachable() async throws {
        let adapter = SwiftkubeApiAdapter(resolver: { _ in
            throw FakeError.notFound
        })

        let status = try await adapter.probeHealth(clusterId: ClusterId("missing"))

        XCTAssertEqual(status.state, .unreachable)
        XCTAssertEqual(status.clusterId, ClusterId("missing"))
        XCTAssertNotNil(status.detail)
    }

    func test_serverVersion_whenResolverThrows_propagatesError() async {
        let adapter = SwiftkubeApiAdapter(resolver: { _ in
            throw FakeError.notFound
        })

        do {
            _ = try await adapter.serverVersion(clusterId: ClusterId("missing"))
            XCTFail("Expected error to be thrown")
        } catch {
            // Any error is acceptable — the resolver error propagates unchanged
            // for serverVersion (no HealthStatus wrapping).
            XCTAssertTrue(error is FakeError)
        }
    }
}
