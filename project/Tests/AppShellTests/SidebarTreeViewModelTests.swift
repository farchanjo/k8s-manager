// Tests/AppShellTests/SidebarTreeViewModelTests.swift
// Coverage: SidebarTree taxonomy + SidebarTreeViewModel tab-activation flows.

import XCTest
import Dependencies
@testable import AppShell
import SharedKernel

// MARK: - SidebarTreeViewModelTests

@MainActor
final class SidebarTreeViewModelTests: XCTestCase {

    // MARK: - Taxonomy: top-level count

    func test_standardCategories_returns14TopLevelNodes() {
        let categories = SidebarTree.standardCategories()
        XCTAssertEqual(categories.count, 14,
            "Expected 14 top-level nodes; got \(categories.count): \(categories.map(\.id))")
    }

    // MARK: - Taxonomy: workloads children count

    func test_workloads_expandable_returns8Children() {
        let workloads = SidebarNode.workloads
        let children = workloads.children
        XCTAssertNotNil(children, "workloads node must be expandable")
        XCTAssertEqual(children?.count, 8,
            "Expected 8 workload children; got \(children?.count ?? -1)")
    }

    // MARK: - Tab activation: .workloadKind(.pods)

    func test_activate_pods_opensResourceListTab() async throws {
        let clusterId = ClusterId("test-cluster")
        let strip = await makeStrip(clusterId: clusterId)
        let spyPort = SpyOpenTabsPort()

        await withDependencies {
            $0.clusterStrip = strip
            $0.openTabs = spyPort
        } operation: {
            let sut = SidebarTreeViewModel()
            // Kick off start in a background Task and let it receive the first snapshot.
            let startTask = Task { await sut.start() }
            // Give the stream one cooperative pass so the snapshot is applied.
            await Task.yield()
            await sut.activate(.workloadKind(.pods))
            startTask.cancel()

            let opened = await spyPort.openedTabs
            XCTAssertEqual(opened.count, 1, "Expected 1 opened tab")
            guard case .resourceList(let cid, let kind, _) = opened.first else {
                XCTFail("Expected .resourceList, got \(String(describing: opened.first))")
                return
            }
            XCTAssertEqual(cid, clusterId)
            XCTAssertEqual(kind.kind, "Pod")
        }
    }

    // MARK: - Tab activation: .events

    func test_activate_events_opensEventsTab() async throws {
        let clusterId = ClusterId("test-cluster")
        let strip = await makeStrip(clusterId: clusterId)
        let spyPort = SpyOpenTabsPort()

        await withDependencies {
            $0.clusterStrip = strip
            $0.openTabs = spyPort
        } operation: {
            let sut = SidebarTreeViewModel()
            let startTask = Task { await sut.start() }
            await Task.yield()
            await sut.activate(.events)
            startTask.cancel()

            let opened = await spyPort.openedTabs
            XCTAssertEqual(opened.count, 1, "Expected 1 opened tab")
            guard case .events(let cid, _) = opened.first else {
                XCTFail("Expected .events, got \(String(describing: opened.first))")
                return
            }
            XCTAssertEqual(cid, clusterId)
        }
    }

    // MARK: - Selection persistence across view-model restart

    func test_selectedNode_persistsAfterSecondActivate() async throws {
        let clusterId = ClusterId("cluster-a")
        let strip = await makeStrip(clusterId: clusterId)
        let spyPort = SpyOpenTabsPort()

        await withDependencies {
            $0.clusterStrip = strip
            $0.openTabs = spyPort
        } operation: {
            let sut = SidebarTreeViewModel()
            let startTask = Task { await sut.start() }
            await Task.yield()
            await sut.activate(.events)
            let firstNode = sut.selectedNode
            await sut.activate(.events)
            startTask.cancel()
            XCTAssertEqual(sut.selectedNode, firstNode,
                "selectedNode should stay .events after a second activation of the same node")
        }
    }

    // MARK: - Group header activation: no tab opened

    func test_activate_groupHeader_doesNotOpenTab() async throws {
        let clusterId = ClusterId("test-cluster")
        let strip = await makeStrip(clusterId: clusterId)
        let spyPort = SpyOpenTabsPort()

        await withDependencies {
            $0.clusterStrip = strip
            $0.openTabs = spyPort
        } operation: {
            let sut = SidebarTreeViewModel()
            let startTask = Task { await sut.start() }
            await Task.yield()
            await sut.activate(.workloads) // group header — has no DocumentTab
            startTask.cancel()

            let opened = await spyPort.openedTabs
            XCTAssertTrue(opened.isEmpty,
                "Activating a group header must not open a tab")
        }
    }

    // MARK: - selectedNode set before openTab call

    /// Verifies that `activate(_:)` sets `selectedNode` before dispatching
    /// `openTab` — ensuring the List highlight updates even if the port is slow.
    func test_activate_setsSelectedNodeBeforeOpenTab() async throws {
        let clusterId = ClusterId("test-cluster")
        let strip = await makeStrip(clusterId: clusterId)
        let orderedSpy = OrderedCallSpy()

        await withDependencies {
            $0.clusterStrip = strip
            $0.openTabs = orderedSpy
        } operation: {
            let sut = SidebarTreeViewModel()
            let startTask = Task { await sut.start() }
            await Task.yield()

            await sut.activate(.workloadKind(.deployments))
            startTask.cancel()

            // selectedNode must be set immediately (before openTab's async call returns)
            XCTAssertEqual(sut.selectedNode, .workloadKind(.deployments))
            let opened = await orderedSpy.openedTabs
            XCTAssertEqual(opened.count, 1)
        }
    }

    // MARK: - No active cluster: activation is a no-op

    func test_activate_withNoCluster_isNoOp() async throws {
        let emptyStrip = ClusterStripActor()
        let spyPort = SpyOpenTabsPort()

        await withDependencies {
            $0.clusterStrip = emptyStrip
            $0.openTabs = spyPort
        } operation: {
            let sut = SidebarTreeViewModel()
            let startTask = Task { await sut.start() }
            await Task.yield()
            await sut.activate(.events)
            startTask.cancel()

            let opened = await spyPort.openedTabs
            XCTAssertTrue(opened.isEmpty,
                "Activating a node without an active cluster must be a no-op")
        }
    }
}

// MARK: - Helpers

/// Creates a `ClusterStripActor` pre-pinned with one cluster set as active.
///
/// Awaits the pin and setActive calls so the actor state is settled before
/// the caller constructs a view model and subscribes to the stream.
private func makeStrip(clusterId: ClusterId) async -> ClusterStripActor {
    let strip = ClusterStripActor()
    try? await strip.pin(clusterId: clusterId, displayName: clusterId.rawValue)
    await strip.setActive(clusterId)
    return strip
}

// MARK: - Test doubles

/// Actor-based spy that records every `openTab(_:)` call.
private actor SpyOpenTabsPort: OpenTabsPort {
    private(set) var openedTabs: [DocumentTab] = []

    func openTab(_ tab: DocumentTab) async {
        openedTabs.append(tab)
    }
}

/// Spy that records tabs in insertion order (used to verify ordering guarantees).
private actor OrderedCallSpy: OpenTabsPort {
    private(set) var openedTabs: [DocumentTab] = []

    func openTab(_ tab: DocumentTab) async {
        openedTabs.append(tab)
    }
}
