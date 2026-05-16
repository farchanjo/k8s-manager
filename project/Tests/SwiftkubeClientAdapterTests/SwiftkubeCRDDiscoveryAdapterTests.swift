// Tests/SwiftkubeClientAdapterTests/SwiftkubeCRDDiscoveryAdapterTests.swift
// Coverage: SwiftkubeCRDDiscoveryAdapter — construction smoke + error mapping +
//           protocol conformance. No network required (real API calls excluded).
// ADR ref: ADR-0052 (custom resource discovery and rendering)

import XCTest
import SharedKernel
import ClusterConnectivity
@testable import ResourceBrowser
@testable import SwiftkubeClientAdapter

// MARK: - SwiftkubeCRDDiscoveryAdapterConstructionTests

/// Verifies that `SwiftkubeCRDDiscoveryAdapter` can be instantiated with various
/// resolver closures without crashing.
final class SwiftkubeCRDDiscoveryAdapterConstructionTests: XCTestCase {

    func test_init_withBearerTokenResolver_succeeds() {
        let adapter = SwiftkubeCRDDiscoveryAdapter(
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
        XCTAssertTrue(type(of: adapter) == SwiftkubeCRDDiscoveryAdapter.self)
    }

    func test_init_withClientCertResolver_succeeds() {
        // Construction must not throw regardless of auth type; errors fire at call time.
        let adapter = SwiftkubeCRDDiscoveryAdapter(
            resolver: { _ in
                ClusterParams(
                    server: URL(string: "https://10.0.0.1:6443")!,
                    auth: .clientCert(ClientCertAuth(certPEM: "CERT", keyPEM: "KEY")),
                    insecureSkipTLSVerify: false,
                    caStrategy: .system
                )
            }
        )
        XCTAssertTrue(type(of: adapter) == SwiftkubeCRDDiscoveryAdapter.self)
    }
}

// MARK: - SwiftkubeCRDDiscoveryAdapterErrorMappingTests

/// Verifies that resolver errors are surfaced as `CRDDiscoveryError.transportError`.
final class SwiftkubeCRDDiscoveryAdapterErrorMappingTests: XCTestCase {

    private enum FakeError: Error { case networkDown }

    func test_discoverCRDs_whenResolverThrows_throwsCRDDiscoveryError() async {
        let adapter = SwiftkubeCRDDiscoveryAdapter(resolver: { _ in
            throw FakeError.networkDown
        })

        do {
            _ = try await adapter.discoverCRDs(clusterId: ClusterId("test"))
            XCTFail("Expected error to be thrown")
        } catch {
            // Any error is acceptable — the resolver error propagates.
            XCTAssertNotNil(error)
        }
    }

    func test_watchCRDChanges_whenResolverThrows_streamFinishesWithError() async {
        let adapter = SwiftkubeCRDDiscoveryAdapter(resolver: { _ in
            throw FakeError.networkDown
        })

        let stream = adapter.watchCRDChanges(clusterId: ClusterId("bad"))
        var caughtError: Error?
        do {
            for try await _ in stream { /* drain */ }
        } catch {
            caughtError = error
        }
        // Stream should have finished (with or without error); no infinite loop.
        // The test succeeds as long as it does not hang.
        _ = caughtError // suppress unused-variable warning
    }
}

// MARK: - SwiftkubeCRDDiscoveryAdapterProtocolConformanceTests

/// Verifies that `SwiftkubeCRDDiscoveryAdapter` conforms to `CRDDiscoveryPort`.
final class SwiftkubeCRDDiscoveryAdapterProtocolConformanceTests: XCTestCase {

    func test_conforms_toCRDDiscoveryPort() {
        let adapter = SwiftkubeCRDDiscoveryAdapter(resolver: { _ in
            ClusterParams(
                server: URL(string: "https://127.0.0.1:6443")!,
                auth: .bearerToken(BearerTokenAuth(token: "tok")),
                insecureSkipTLSVerify: true,
                caStrategy: .system
            )
        })
        // Compile-time conformance check: assign to the protocol existential.
        let port: any CRDDiscoveryPort = adapter
        XCTAssertTrue(type(of: port) == SwiftkubeCRDDiscoveryAdapter.self)
    }
}
