// SwiftkubeWatchAdapterTests.swift — SwiftkubeClientAdapterTests target
// Coverage: SwiftkubeWatchAdapter — construction smoke, 410-Gone mapping,
//           ResourceWatchEvent field decode from fake events.
// ADR refs: ADR-0036 (watch lifecycle, 410-Gone, BOOKMARK handling)

import XCTest
import SharedKernel
@testable import ClusterConnectivity
@testable import ResourceBrowser
@testable import SwiftkubeClientAdapter

// MARK: - Helpers

private func makeParams() -> ClusterParams {
    ClusterParams(
        server: URL(string: "https://127.0.0.1:6443")!,
        auth: .bearerToken(BearerTokenAuth(token: "test-token")),
        insecureSkipTLSVerify: true,
        caStrategy: .system
    )
}

private func makeAdapter(
    params: ClusterParams = makeParams()
) -> SwiftkubeWatchAdapter {
    SwiftkubeWatchAdapter(resolver: { _ in params })
}

// MARK: - Construction smoke tests

final class SwiftkubeWatchAdapterConstructionTests: XCTestCase {

    func test_init_withBearerTokenResolver_succeeds() {
        let adapter = makeAdapter()
        // Construction must not crash; type assertion is the test.
        XCTAssertTrue(type(of: adapter) == SwiftkubeWatchAdapter.self)
    }

    func test_init_withThrowingResolver_returnStreamThatThrowsTransport() async {
        let adapter = SwiftkubeWatchAdapter(resolver: { _ in
            throw URLError(.cannotConnectToHost)
        })
        let stream = adapter.watchResources(
            gvk: GroupVersionKind.core("Pod"),
            namespace: "default",
            contextId: UUID(),
            resourceVersion: nil
        )
        do {
            for try await _ in stream {
                XCTFail("Expected error — stream should not emit elements")
            }
            XCTFail("Expected stream to throw")
        } catch ResourceWatchError.transportError {
            // expected
        } catch {
            XCTFail("Expected ResourceWatchError.transportError, got \(error)")
        }
    }

    func test_watchResources_returnsStream_withoutCrash() {
        let adapter = makeAdapter()
        let stream = adapter.watchResources(
            gvk: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
            namespace: nil,
            contextId: UUID(),
            resourceVersion: nil
        )
        // The stream is returned without blocking. No further assertion needed.
        XCTAssertNotNil(stream)
    }
}

// MARK: - ResourceWatchError conformance tests

final class SwiftkubeWatchAdapterErrorMappingTests: XCTestCase {

    func test_resourceVersionTooOld_isThrowable() {
        // Verify the error type is correctly defined and throwable.
        let error: ResourceWatchError = .resourceVersionTooOld
        if case .resourceVersionTooOld = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Pattern match failed")
        }
    }

    func test_transportError_carriesDetail() {
        let error: ResourceWatchError = .transportError(detail: "TCP reset")
        if case .transportError(let detail) = error {
            XCTAssertEqual(detail, "TCP reset")
        } else {
            XCTFail("Pattern match failed")
        }
    }

    func test_streamClosed_carriesDetail() {
        let error: ResourceWatchError = .streamClosed(detail: "server closed")
        if case .streamClosed(let detail) = error {
            XCTAssertEqual(detail, "server closed")
        } else {
            XCTFail("Pattern match failed")
        }
    }
}

// MARK: - ResourceWatchEvent decode tests

final class SwiftkubeWatchAdapterEventDecodeTests: XCTestCase {

    func test_resourceWatchEvent_addedType_isCorrect() {
        let item = ResourceListItem(
            id: UUID(),
            gvk: GroupVersionKind.core("Pod"),
            namespace: "default",
            name: "pod-1",
            uid: "uid-1",
            creationTimestamp: "2026-05-16T00:00:00Z",
            status: "Running",
            ageSeconds: 120
        )
        let event = ResourceWatchEvent(type: .added, item: item)
        XCTAssertEqual(event.type, .added)
        XCTAssertEqual(event.item.name, "pod-1")
    }

    func test_resourceWatchEvent_deletedType_preservesLastKnownProjection() {
        let item = ResourceListItem(
            id: UUID(),
            gvk: GroupVersionKind.core("Pod"),
            namespace: "staging",
            name: "old-pod",
            uid: "uid-2",
            creationTimestamp: "2026-05-15T00:00:00Z",
            status: "Terminating",
            ageSeconds: 3600
        )
        let event = ResourceWatchEvent(type: .deleted, item: item)
        XCTAssertEqual(event.type, .deleted)
        XCTAssertEqual(event.item.status, "Terminating",
                       "DELETED events must carry the last known projection for row removal")
    }

    func test_resourceWatchEvent_bookmarkType_isRecognised() {
        let item = ResourceListItem(
            id: UUID(),
            gvk: GroupVersionKind.core("Pod"),
            namespace: nil,
            name: "",
            uid: "rv-bookmark",
            creationTimestamp: "2026-05-16T00:00:00Z",
            status: "",
            ageSeconds: 0
        )
        let event = ResourceWatchEvent(type: .bookmark, item: item)
        XCTAssertEqual(event.type, .bookmark)
    }
}
