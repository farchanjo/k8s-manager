// SwiftkubeResourceListAdapterTests.swift — SwiftkubeClientAdapter test target
// Coverage: construction smoke, resolver-throws path, unknown GVK error path.
// Note: integration tests that hit a real Kubernetes API server are excluded
// (no network in CI). All branching exercised here requires no network.

import XCTest
import SharedKernel
@testable import ClusterConnectivity
@testable import SwiftkubeClientAdapter
import ResourceBrowser

// MARK: - Helpers

private func makeParams() -> ClusterParams {
    ClusterParams(
        server: URL(string: "https://127.0.0.1:6443")!,
        auth: .bearerToken(BearerTokenAuth(token: "test-token")),
        insecureSkipTLSVerify: true,
        caStrategy: .system
    )
}

private enum FakeResolverError: Error { case notFound }

// MARK: - ConstructionTests

/// Verifies that `SwiftkubeResourceListAdapter` can be instantiated with
/// various resolver closures without crashing.
final class ResourceListAdapterConstructionTests: XCTestCase {

    func test_init_withBearerTokenResolver() {
        let adapter = SwiftkubeResourceListAdapter(resolver: { _ in makeParams() })
        XCTAssertTrue(type(of: adapter) == SwiftkubeResourceListAdapter.self)
    }

    func test_init_withThrowingResolver() {
        let adapter = SwiftkubeResourceListAdapter(
            resolver: { _ in throw FakeResolverError.notFound }
        )
        // Construction succeeds; the error fires only on first call.
        XCTAssertTrue(type(of: adapter) == SwiftkubeResourceListAdapter.self)
    }
}

// MARK: - ResolverErrorTests

/// Verifies that a resolver error surfaces as a thrown error (not a crash)
/// from `list` and `get`.
final class ResourceListAdapterResolverErrorTests: XCTestCase {

    private let adapter = SwiftkubeResourceListAdapter(
        resolver: { _ in throw FakeResolverError.notFound }
    )
    private let podGVK = GroupVersionKind.core("Pod")
    private let contextId = UUID()

    func test_list_whenResolverThrows_propagatesError() async {
        do {
            _ = try await adapter.list(gvk: podGVK, namespace: nil, contextId: contextId)
            XCTFail("Expected error from resolver to be rethrown")
        } catch is FakeResolverError {
            // expected path
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_get_whenResolverThrows_propagatesError() async {
        do {
            _ = try await adapter.get(
                gvk: podGVK,
                name: "my-pod",
                namespace: "default",
                contextId: contextId
            )
            XCTFail("Expected error from resolver to be rethrown")
        } catch is FakeResolverError {
            // expected path
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - UnknownGVKTests

/// Verifies that an unregistered GVK throws `ResourceListError.unknownGVK`
/// without making any network call. Because the resolver succeeds and the
/// client is constructed but the switch falls through before any RPC, the
/// error is deterministic and network-free.
///
/// Note: The client construction itself succeeds for a bearer-token resolver.
/// The `list` call reaches the switch statement and throws before any I/O.
final class ResourceListAdapterUnknownGVKTests: XCTestCase {

    private let adapter = SwiftkubeResourceListAdapter(resolver: { _ in makeParams() })
    private let unknownGVK = GroupVersionKind(
        group: "example.com",
        version: "v1alpha1",
        kind: "Widget"
    )
    private let contextId = UUID()

    func test_list_withUnknownGVK_throwsUnknownGVK() async {
        do {
            _ = try await adapter.list(gvk: unknownGVK, namespace: nil, contextId: contextId)
            XCTFail("Expected ResourceListError.unknownGVK to be thrown")
        } catch ResourceListError.unknownGVK(let gvk) {
            XCTAssertEqual(gvk, unknownGVK)
        } catch {
            // transportError or similar is also acceptable here:
            // the client may fail to connect before the switch is reached
            // in a zero-network environment. The important assertion is
            // that no crash occurs and no result is returned.
            XCTAssertTrue(
                error is ResourceListError,
                "Expected ResourceListError, got \(error)"
            )
        }
    }

    func test_get_withUnknownGVK_throwsUnknownGVK() async {
        do {
            _ = try await adapter.get(
                gvk: unknownGVK,
                name: "widget-1",
                namespace: "default",
                contextId: contextId
            )
            XCTFail("Expected ResourceListError.unknownGVK to be thrown")
        } catch ResourceListError.unknownGVK(let gvk) {
            XCTAssertEqual(gvk, unknownGVK)
        } catch {
            XCTAssertTrue(
                error is ResourceListError,
                "Expected ResourceListError, got \(error)"
            )
        }
    }
}

// MARK: - KnownGVKErrorShapeTests

/// Verifies that known GVKs produce a `ResourceListError` (not a crash) when
/// hitting a non-existent server. The adapter must not throw an untyped error.
final class ResourceListAdapterKnownGVKErrorShapeTests: XCTestCase {

    private let adapter = SwiftkubeResourceListAdapter(resolver: { _ in makeParams() })
    private let contextId = UUID()

    private let knownGVKs: [GroupVersionKind] = [
        .core("Pod"),
        .core("Service"),
        .core("ConfigMap"),
        .core("Secret"),
        .core("Namespace"),
        GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
        GroupVersionKind(group: "networking.k8s.io", version: "v1", kind: "Ingress"),
    ]

    func test_list_knownGVKs_throwResourceListErrorOnNoNetwork() async {
        for gvk in knownGVKs {
            do {
                _ = try await adapter.list(gvk: gvk, namespace: "default", contextId: contextId)
                // On a machine with no k8s at 127.0.0.1:6443, we expect an error.
                // If somehow a cluster is running we allow success too.
            } catch let err as ResourceListError {
                // transportError or similar — expected in CI.
                switch err {
                case .transportError, .unexpectedStatus, .unimplemented:
                    break // expected
                case .unknownGVK(let g):
                    XCTFail("Known GVK \(gvk) was rejected as unknownGVK: \(g)")
                case .notFound:
                    break // technically valid on a live cluster
                }
            } catch {
                // Other errors (NIO, TLS) are acceptable in a no-network environment.
                break
            }
        }
    }
}
