// Tests/AppShellTests/DockedTerminalPaneActorTests.swift
// Target: AppShellTests
// Coverage: ADR-0057 docked terminal pane actor invariants
//
// Verifies:
// 1. openTab inserts a new tab and sets it as activeTabId.
// 2. Opening a duplicate nodeDebug tab (same cluster + node) focuses the existing tab.
// 3. closeTab removes the tab and adjusts activeTabId to the predecessor.
// 4. updateConnectionState mutates the correct tab without touching others.
// 5. setPaneHeight clamps to the 120 pt minimum.
// 6. loadFromDisk restores tabs with connectionState == .closed (cold-launch invariant).
// 7. loadFromDisk on a missing file leaves state empty (first-launch default).

import XCTest
@testable import AppShell
import SharedKernel

final class DockedTerminalPaneActorTests: XCTestCase {

    // MARK: Helpers

    private var tmpFile: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/docked-terminal-pane.json")
    }

    private func makeActor(persistenceURL: URL? = nil) -> DockedTerminalPaneActor {
        DockedTerminalPaneActor(persistenceURL: persistenceURL ?? tmpFile)
    }

    private func makeTab(
        kind: DockedTerminalKind = .podExec,
        label: String = "Pod: test",
        clusterId: ClusterId = ClusterId(UUID().uuidString),
        targetNodeName: String? = nil,
        targetPodName: String? = "test-pod",
        targetPodNamespace: String? = "default"
    ) -> DockedTerminalTab {
        DockedTerminalTab(
            kind: kind,
            label: label,
            clusterId: clusterId,
            targetNodeName: targetNodeName,
            targetPodNamespace: targetPodNamespace,
            targetPodName: targetPodName
        )
    }

    // MARK: - openTab

    func test_openTab_insertsTabAndSetsActiveId() async {
        let sut = makeActor()
        let tab = makeTab(label: "Pod: api")

        await sut.openTab(tab)

        let tabs = await sut.state.tabs
        let activeId = await sut.state.activeTabId
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first?.id, tab.id)
        XCTAssertEqual(activeId, tab.id)
    }

    func test_openTab_multipleTabsOrderedByInsertion() async {
        let sut = makeActor()
        let clusterId = ClusterId(UUID().uuidString)
        let tab1 = makeTab(kind: .podExec, label: "Pod: first", clusterId: clusterId, targetPodName: "p1")
        let tab2 = makeTab(kind: .podExec, label: "Pod: second", clusterId: clusterId, targetPodName: "p2")

        await sut.openTab(tab1)
        await sut.openTab(tab2)

        let tabs = await sut.state.tabs
        let activeId2 = await sut.state.activeTabId
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].id, tab1.id)
        XCTAssertEqual(tabs[1].id, tab2.id)
        XCTAssertEqual(activeId2, tab2.id)
    }

    // MARK: - Duplicate nodeDebug prevention

    func test_openTab_duplicateNodeDebug_focusesExistingTab() async {
        let sut = makeActor()
        let clusterId = ClusterId(UUID().uuidString)
        let original = DockedTerminalTab(
            kind: .nodeDebug,
            label: "Node: worker-01",
            clusterId: clusterId,
            targetNodeName: "worker-01"
        )
        await sut.openTab(original)

        let duplicate = DockedTerminalTab(
            kind: .nodeDebug,
            label: "Node: worker-01",
            clusterId: clusterId,
            targetNodeName: "worker-01"
        )
        await sut.openTab(duplicate)

        let tabs = await sut.state.tabs
        let activeId = await sut.state.activeTabId
        XCTAssertEqual(tabs.count, 1, "Duplicate nodeDebug must not create a second tab")
        XCTAssertEqual(activeId, original.id)
    }

    func test_openTab_nodeDebugDifferentNode_createsNewTab() async {
        let sut = makeActor()
        let clusterId = ClusterId(UUID().uuidString)
        let worker01 = DockedTerminalTab(
            kind: .nodeDebug, label: "Node: worker-01",
            clusterId: clusterId, targetNodeName: "worker-01"
        )
        let worker02 = DockedTerminalTab(
            kind: .nodeDebug, label: "Node: worker-02",
            clusterId: clusterId, targetNodeName: "worker-02"
        )

        await sut.openTab(worker01)
        await sut.openTab(worker02)

        let tabs = await sut.state.tabs
        XCTAssertEqual(tabs.count, 2)
    }

    // MARK: - closeTab

    func test_closeTab_removesTabAndFocusesPredecessor() async {
        let sut = makeActor()
        let clusterId = ClusterId(UUID().uuidString)
        let tab1 = makeTab(kind: .podExec, label: "Pod: a", clusterId: clusterId, targetPodName: "a")
        let tab2 = makeTab(kind: .podExec, label: "Pod: b", clusterId: clusterId, targetPodName: "b")

        await sut.openTab(tab1)
        await sut.openTab(tab2)
        await sut.closeTab(tab2.id)

        let tabs = await sut.state.tabs
        let activeId = await sut.state.activeTabId
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(activeId, tab1.id)
    }

    func test_closeTab_lastTab_clearsActiveTabId() async {
        let sut = makeActor()
        let tab = makeTab()

        await sut.openTab(tab)
        await sut.closeTab(tab.id)

        let tabs = await sut.state.tabs
        let activeId = await sut.state.activeTabId
        XCTAssertTrue(tabs.isEmpty)
        XCTAssertNil(activeId)
    }

    func test_closeTab_unknownId_isNoOp() async {
        let sut = makeActor()
        let tab = makeTab()
        await sut.openTab(tab)

        await sut.closeTab(UUID()) // non-existent id

        let tabs = await sut.state.tabs
        XCTAssertEqual(tabs.count, 1)
    }

    // MARK: - updateConnectionState

    func test_updateConnectionState_mutatesTargetTabOnly() async {
        let sut = makeActor()
        let clusterId = ClusterId(UUID().uuidString)
        let tab1 = makeTab(kind: .podExec, label: "Pod: a", clusterId: clusterId, targetPodName: "a")
        let tab2 = makeTab(kind: .podExec, label: "Pod: b", clusterId: clusterId, targetPodName: "b")

        await sut.openTab(tab1)
        await sut.openTab(tab2)

        await sut.updateConnectionState(tabId: tab1.id, connectionState: .open)

        let tabs = await sut.state.tabs
        XCTAssertEqual(tabs.first(where: { $0.id == tab1.id })?.connectionState, .open)
        XCTAssertEqual(tabs.first(where: { $0.id == tab2.id })?.connectionState, .opening)
    }

    // MARK: - setPaneHeight

    func test_setPaneHeight_clampedToMinimum() async {
        let sut = makeActor()

        await sut.setPaneHeight(50)

        let height = await sut.state.paneHeight
        XCTAssertEqual(height, 120, accuracy: 0.01)
    }

    func test_setPaneHeight_validValueAccepted() async {
        let sut = makeActor()

        await sut.setPaneHeight(300)

        let height = await sut.state.paneHeight
        XCTAssertEqual(height, 300, accuracy: 0.01)
    }

    // MARK: - Persistence round-trip

    func test_persistence_roundTrip_tabsRestoredAsClosed() async throws {
        let url = tmpFile
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Write state via the actor
        let writer = DockedTerminalPaneActor(persistenceURL: url)
        let clusterId = ClusterId(UUID().uuidString)
        var tab = DockedTerminalTab(
            kind: .nodeDebug, label: "Node: worker-01",
            clusterId: clusterId, targetNodeName: "worker-01",
            connectionState: .open
        )
        await writer.openTab(tab)
        // Trigger save immediately by calling the internal path via a height update
        await writer.setPaneHeight(200)
        // Allow the debounce to settle
        try await Task.sleep(for: .milliseconds(700))

        // Read state via a fresh actor
        let reader = DockedTerminalPaneActor(persistenceURL: url)
        try await reader.loadFromDisk()

        let restoredTabs = await reader.state.tabs
        XCTAssertEqual(restoredTabs.count, 1)
        XCTAssertEqual(restoredTabs.first?.connectionState, .closed,
                       "All restored tabs must be .closed on cold launch (ADR-0057 §Persistence)")
        XCTAssertNil(restoredTabs.first?.sessionActorId,
                     "sessionActorId must be nil after cold-launch restore")
        _ = tab // suppress unused warning
    }

    func test_loadFromDisk_missingFile_keepsDefaultState() async throws {
        let sut = makeActor(persistenceURL: tmpFile) // file does not exist

        try await sut.loadFromDisk()

        let tabs = await sut.state.tabs
        XCTAssertTrue(tabs.isEmpty)
    }
}
