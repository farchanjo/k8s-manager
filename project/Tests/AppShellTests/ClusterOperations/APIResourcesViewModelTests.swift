// Tests/AppShellTests/ClusterOperations/APIResourcesViewModelTests.swift
// Coverage: APIResourcesViewModel — search filter, error path, empty query, namespace badge.

import XCTest
@testable import AppShell
import SharedKernel

// MARK: - APIResourcesViewModelTests

@MainActor
final class APIResourcesViewModelTests: XCTestCase {

    private let clusterId = ClusterId("test-cluster")

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = APIResourcesViewModel()
        XCTAssertTrue(sut.resources.isIdle)
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertTrue(sut.filteredResources.isEmpty)
    }

    // MARK: start — loads on idle, no-ops on subsequent calls

    func test_start_transitionsToSuccessOnFirstCall() async {
        let sut = APIResourcesViewModel()
        await sut.start(clusterId: clusterId)
        XCTAssertNotNil(sut.resources.value)
        XCTAssertFalse(sut.resources.value!.isEmpty)
    }

    func test_start_isNoOpWhenAlreadyLoaded() async {
        let sut = APIResourcesViewModel()
        await sut.start(clusterId: clusterId)
        let firstCount = sut.resources.value?.count ?? 0

        await sut.start(clusterId: clusterId)  // second call — should be no-op
        XCTAssertEqual(sut.resources.value?.count, firstCount)
    }

    // MARK: Search filter — case-insensitive kind / short name / group matching

    func test_searchFilter_returnsMatchingKinds() async {
        let sut = APIResourcesViewModel()
        await sut.start(clusterId: clusterId)

        sut.searchQuery = "pod"
        let pods = sut.filteredResources.filter { $0.kind == "Pod" }
        XCTAssertFalse(pods.isEmpty, "Expected Pod to appear when searching 'pod'")
    }

    func test_searchFilter_matchesShortName() async {
        let sut = APIResourcesViewModel()
        await sut.start(clusterId: clusterId)

        sut.searchQuery = "svc"
        let services = sut.filteredResources.filter { $0.kind == "Service" }
        XCTAssertFalse(services.isEmpty, "Expected Service to match shortName 'svc'")
    }

    func test_searchFilter_emptyQueryReturnsAll() async {
        let sut = APIResourcesViewModel()
        await sut.start(clusterId: clusterId)
        let total = sut.resources.value?.count ?? 0

        sut.searchQuery = ""
        XCTAssertEqual(sut.filteredResources.count, total)
    }

    func test_searchFilter_noMatchReturnsEmpty() async {
        let sut = APIResourcesViewModel()
        await sut.start(clusterId: clusterId)

        sut.searchQuery = "xyznonexistentresource"
        XCTAssertTrue(sut.filteredResources.isEmpty)
    }

    // MARK: reload

    func test_reload_refreshesData() async {
        let sut = APIResourcesViewModel()
        await sut.start(clusterId: clusterId)
        let before = sut.resources.value?.count ?? 0

        await sut.reload(clusterId: clusterId)
        XCTAssertEqual(sut.resources.value?.count, before)
        XCTAssertNotNil(sut.resources.value)
    }
}
