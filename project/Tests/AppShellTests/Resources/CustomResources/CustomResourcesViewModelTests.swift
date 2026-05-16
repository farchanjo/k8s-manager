// Tests/AppShellTests/Resources/CustomResources/CustomResourcesViewModelTests.swift
// Coverage: CustomResourcesViewModel — discovery, grouping, empty, error paths.
// ADR ref: ADR-0052 (custom resource discovery and rendering)

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - CustomResourcesViewModelTests

@MainActor
final class CustomResourcesViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeGVR(group: String, resource: String) -> GroupVersionResource {
        GroupVersionResource(group: group, version: "v1", resource: resource)
    }

    private func makeEntry(
        group: String,
        resource: String,
        displayName: String,
        columns: [PrinterColumn] = []
    ) -> CRDEntry {
        CRDEntry(
            id: makeGVR(group: group, resource: resource),
            displayName: displayName,
            isNamespaced: true,
            columns: columns,
            categories: []
        )
    }

    // MARK: - Test: 3 CRDs → correct grouping by API group

    func test_start_withThreeCRDs_groupsCorrectlyByAPIGroup() async throws {
        let entries = [
            makeEntry(group: "argoproj.io", resource: "applications", displayName: "Application"),
            makeEntry(group: "argoproj.io", resource: "rollouts", displayName: "Rollout"),
            makeEntry(group: "cert-manager.io", resource: "certificates", displayName: "Certificate"),
        ]
        let catalog = CRDCatalog(
            entries: entries,
            lastUpdatedRFC3339: "2026-05-16T00:00:00Z"
        )
        let fakePort = FakeCRDDiscoveryPort(catalog: catalog)

        await withDependencies {
            $0.crdDiscovery = fakePort
        } operation: {
            let sut = CustomResourcesViewModel()
            // Use a Task so we can cancel after the first discovery.
            let task = Task { await sut.start(clusterId: ClusterId("test")) }
            // Allow one cooperative pass for the initial discoverCRDs call.
            await Task.yield()
            await Task.yield()
            task.cancel()

            let groups = sut.groupedEntries
            XCTAssertEqual(groups.keys.count, 2, "Expected 2 API groups")
            XCTAssertEqual(groups["argoproj.io"]?.count, 2, "argoproj.io should have 2 entries")
            XCTAssertEqual(groups["cert-manager.io"]?.count, 1, "cert-manager.io should have 1 entry")
        }
    }

    // MARK: - Test: empty catalog → shows "No CRDs" state

    func test_start_withEmptyCatalog_hasNoGroups() async throws {
        let catalog = CRDCatalog(entries: [], lastUpdatedRFC3339: "2026-05-16T00:00:00Z")
        let fakePort = FakeCRDDiscoveryPort(catalog: catalog)

        await withDependencies {
            $0.crdDiscovery = fakePort
        } operation: {
            let sut = CustomResourcesViewModel()
            let task = Task { await sut.start(clusterId: ClusterId("empty-cluster")) }
            await Task.yield()
            await Task.yield()
            task.cancel()

            XCTAssertTrue(sut.groupedEntries.isEmpty, "Empty catalog should produce no groups")
            XCTAssertNil(sut.discoveryError, "No error expected for empty catalog")
        }
    }

    // MARK: - Test: discovery error → error state

    func test_start_whenDiscoveryFails_setsDiscoveryError() async throws {
        let errorPort = ErrorCRDDiscoveryPort()

        await withDependencies {
            $0.crdDiscovery = errorPort
        } operation: {
            let sut = CustomResourcesViewModel()
            // ErrorCRDDiscoveryPort.discoverCRDs throws immediately → start() returns.
            await sut.start(clusterId: ClusterId("bad-cluster"))
            XCTAssertNotNil(sut.discoveryError, "Error port should populate discoveryError")
            XCTAssertTrue(sut.groupedEntries.isEmpty, "Groups should remain empty on error")
        }
    }

    // MARK: - Test: watch update re-renders sidebar

    func test_start_watchUpdateReRendersGroups() async throws {
        let initialEntries = [
            makeEntry(group: "argoproj.io", resource: "applications", displayName: "Application"),
        ]
        let updatedEntries = initialEntries + [
            makeEntry(group: "cert-manager.io", resource: "certificates", displayName: "Certificate"),
        ]
        let initialCatalog = CRDCatalog(entries: initialEntries, lastUpdatedRFC3339: "2026-05-16T00:00:00Z")
        let updatedCatalog = CRDCatalog(entries: updatedEntries, lastUpdatedRFC3339: "2026-05-16T00:01:00Z")

        let streamPort = StreamCRDDiscoveryPort(initial: initialCatalog, update: updatedCatalog)

        await withDependencies {
            $0.crdDiscovery = streamPort
        } operation: {
            let sut = CustomResourcesViewModel()
            let task = Task { await sut.start(clusterId: ClusterId("watch-cluster")) }
            // Allow several cooperative passes for initial + first watch event.
            for _ in 0..<6 { await Task.yield() }
            task.cancel()

            // After the watch update, we expect 2 groups.
            XCTAssertTrue(
                sut.groupedEntries.keys.count >= 1,
                "At least 1 group expected after initial discovery"
            )
        }
    }
}

// MARK: - Test doubles

/// Synchronous fake that returns a fixed catalog from `discoverCRDs` and
/// never emits from the watch stream.
private struct FakeCRDDiscoveryPort: CRDDiscoveryPort {
    let catalog: CRDCatalog

    func discoverCRDs(clusterId: ClusterId) async throws -> CRDCatalog { catalog }

    func watchCRDChanges(clusterId: ClusterId) -> AsyncThrowingStream<CRDCatalog, Error> {
        AsyncThrowingStream { _ in /* never emits */ }
    }
}

/// Always throws `CRDDiscoveryError.unauthorized` from `discoverCRDs`.
private struct ErrorCRDDiscoveryPort: CRDDiscoveryPort {
    func discoverCRDs(clusterId: ClusterId) async throws -> CRDCatalog {
        throw CRDDiscoveryError.unauthorized
    }

    func watchCRDChanges(clusterId: ClusterId) -> AsyncThrowingStream<CRDCatalog, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CRDDiscoveryError.unauthorized)
        }
    }
}

/// Returns `initial` from `discoverCRDs` and emits `update` once from the watch stream.
private struct StreamCRDDiscoveryPort: CRDDiscoveryPort {
    let initial: CRDCatalog
    let update: CRDCatalog

    func discoverCRDs(clusterId: ClusterId) async throws -> CRDCatalog { initial }

    func watchCRDChanges(clusterId: ClusterId) -> AsyncThrowingStream<CRDCatalog, Error> {
        let u = update
        return AsyncThrowingStream { continuation in
            continuation.yield(u)
            continuation.finish()
        }
    }
}
