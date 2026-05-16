// Tests/HelmManagementTests/ReleaseReaderActorTests.swift — helm_management
// ADR ref: ADR-0015 §Phase 1 §Grouping revisions

import XCTest
import Dependencies
import SharedKernel
@testable import HelmManagement

// MARK: - ReleaseReaderActorTests

final class ReleaseReaderActorTests: XCTestCase {

    // MARK: - list(in:) — cache miss populates from store

    func test_listPopulatesFromStoreOnCacheMiss() async throws {
        let expected = [makeFakeRelease(version: 1, namespace: "default")]
        let stub = StubHelmReleaseStore(releases: expected)
        let actor = ReleaseReaderActor()
        let result = try await withDependencies {
            $0.helmReleaseStore = stub
        } operation: {
            try await actor.list(in: .init("ctx-a"), namespace: "default")
        }
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].version, 1)
    }

    // MARK: - list(in:) — cache hit avoids second store call

    func test_listReturnsCachedResultWithoutSecondStoreCall() async throws {
        let stub = CountingHelmReleaseStore(releases: [makeFakeRelease(version: 1, namespace: "staging")])
        let actor = ReleaseReaderActor()
        try await withDependencies {
            $0.helmReleaseStore = stub
        } operation: {
            _ = try await actor.list(in: .init("ctx-b"), namespace: "staging")
            _ = try await actor.list(in: .init("ctx-b"), namespace: "staging")
            let callCount = await stub.callCount
            XCTAssertEqual(callCount, 1, "Second list must be served from cache")
        }
    }

    // MARK: - history(for:) — returns ordered history entries

    func test_historyReturnsEntriesInRevisionOrder() async throws {
        let releaseId = UUID()
        let v1 = makeFakeRelease(id: releaseId, version: 1, namespace: "prod")
        let v2 = makeFakeRelease(id: UUID(), version: 2, namespace: "prod", status: .deployed)
        let stub = StubHelmReleaseStore(releases: [v2, v1])
        let actor = ReleaseReaderActor()
        let history = try await withDependencies {
            $0.helmReleaseStore = stub
        } operation: {
            try await actor.history(for: releaseId, clusterId: .init("ctx-c"))
        }
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].revision, 1)
        XCTAssertEqual(history[1].revision, 2)
    }

    // MARK: - refresh() — invalidates cache

    func test_refreshClearsCache() async throws {
        let stub = CountingHelmReleaseStore(releases: [makeFakeRelease(version: 1, namespace: "dev")])
        let actor = ReleaseReaderActor()
        try await withDependencies {
            $0.helmReleaseStore = stub
        } operation: {
            _ = try await actor.list(in: .init("ctx-d"), namespace: "dev")
            await actor.refresh()
            _ = try await actor.list(in: .init("ctx-d"), namespace: "dev")
            let callCount = await stub.callCount
            XCTAssertEqual(callCount, 2, "After refresh cache miss must hit store again")
        }
    }
}

// MARK: - Test Doubles

private func makeFakeRelease(
    id: UUID = UUID(),
    version: Int = 1,
    namespace: String = "default",
    status: ReleaseStatus = .deployed
) -> Release {
    Release(
        id: id,
        kubernetesContextId: UUID(),
        name: "my-app",
        namespace: namespace,
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
        manifestYAML: "apiVersion: v1\nkind: ConfigMap\n",
        valuesJSON: "{}",
        hooks: [],
        modifiedAtRFC3339: "2024-01-02T00:00:00Z",
        sourceSecretName: "sh.helm.release.v1.my-app.v\(version)"
    )
}

private struct StubHelmReleaseStore: HelmReleaseStorePort {
    let releases: [Release]

    func listReleases(clusterId: ClusterId, namespace: String?) async throws -> [Release] {
        releases.filter { namespace == nil || $0.namespace == namespace }
    }

    func readRelease(secretName: String, namespace: String, clusterId: ClusterId) async throws -> Release {
        guard let found = releases.first(where: { $0.sourceSecretName == secretName }) else {
            throw HelmReleaseStoreError.notFound(secretName: secretName, namespace: namespace)
        }
        return found
    }

    func writeRelease(_ release: Release, clusterId: ClusterId) async throws {}
}

private actor CountingHelmReleaseStore: HelmReleaseStorePort {
    let releases: [Release]
    private(set) var callCount: Int = 0

    init(releases: [Release]) { self.releases = releases }

    func listReleases(clusterId: ClusterId, namespace: String?) async throws -> [Release] {
        callCount += 1
        return releases.filter { namespace == nil || $0.namespace == namespace }
    }

    func readRelease(secretName: String, namespace: String, clusterId: ClusterId) async throws -> Release {
        throw HelmReleaseStoreError.notFound(secretName: secretName, namespace: namespace)
    }

    func writeRelease(_ release: Release, clusterId: ClusterId) async throws {}
}
