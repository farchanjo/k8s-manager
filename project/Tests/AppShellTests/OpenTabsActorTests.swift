// Tests/AppShellTests/OpenTabsActorTests.swift
// Target: AppShellTests
// Coverage: OpenTabsActor lifecycle + persistence

import XCTest
@testable import AppShell
import SharedKernel

final class OpenTabsActorTests: XCTestCase {

    // MARK: Helpers

    private func makeActor(tmpDir: URL) -> OpenTabsActor {
        OpenTabsActor(
            persistenceURL: tmpDir.appendingPathComponent("open-tabs.json")
        )
    }

    private func makeOverview(_ suffix: String = "a") -> DocumentTab {
        .overview(clusterId: ClusterId(suffix))
    }

    private func makeNodes(_ suffix: String = "a") -> DocumentTab {
        .nodes(clusterId: ClusterId(suffix))
    }

    private var tmpDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - openTab adds to tabs and sets active

    func test_openTab_addsTabAndSetsActive() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let tab = makeOverview()

        await sut.openTab(tab)

        let tabs = await sut.tabs
        let activeId = await sut.activeTabId
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs[0].id, tab.id)
        XCTAssertEqual(activeId, tab.id)
    }

    // MARK: - duplicate openTab → focus, no duplicate

    func test_openTab_duplicateIdentity_focusesOnly() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let tab1 = makeOverview()
        let tab2 = makeNodes()

        await sut.openTab(tab1)
        await sut.openTab(tab2)
        // Open overview again — same identity as tab1.
        await sut.openTab(makeOverview())

        let tabs = await sut.tabs
        let activeId = await sut.activeTabId
        // No duplicate: still only two tabs.
        XCTAssertEqual(tabs.count, 2)
        // Focus moved back to overview.
        XCTAssertEqual(activeId, tab1.id)
    }

    // MARK: - closeTab removes tab and cancels watcher

    func test_closeTab_removesTabAndCancelsWatcher() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let tab = makeOverview()
        await sut.openTab(tab)

        var watcherCancelled = false
        let watcherTask = Task<Void, Never> {
            // Simulate a long-lived watcher; records cancellation.
            try? await Task.sleep(for: .seconds(60))
            watcherCancelled = true
        }
        await sut.registerWatcher(for: tab.id, task: watcherTask)

        await sut.closeTab(tab.id)

        // Give the task a moment to observe cancellation.
        try await Task.sleep(for: .milliseconds(50))

        let tabs = await sut.tabs
        let activeId = await sut.activeTabId
        XCTAssertTrue(tabs.isEmpty)
        XCTAssertNil(activeId)
        XCTAssertTrue(watcherTask.isCancelled)
    }

    // MARK: - reorderTabs preserves identities

    func test_reorderTabs_preservesIdentitiesInNewOrder() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let t1 = makeOverview("x")
        let t2 = makeNodes("x")
        let t3: DocumentTab = .namespaces(clusterId: ClusterId("x"))
        await sut.openTab(t1)
        await sut.openTab(t2)
        await sut.openTab(t3)

        await sut.reorderTabs([t3.id, t1.id, t2.id])

        let tabs = await sut.tabs
        XCTAssertEqual(tabs.map(\.id), [t3.id, t1.id, t2.id])
    }

    // MARK: - save/load roundtrip

    func test_saveLoad_roundtrip() async throws {
        let dir = tmpDir
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let sut = makeActor(tmpDir: dir)
        let tab1 = makeOverview("cluster-1")
        let tab2 = makeNodes("cluster-1")
        await sut.openTab(tab1)
        await sut.openTab(tab2)

        // Allow debounce to fire (> 500 ms).
        try await Task.sleep(for: .milliseconds(700))

        // Load into a fresh actor pointing at the same file.
        let sut2 = makeActor(tmpDir: dir)
        try await sut2.loadFromDisk()

        let restoredTabs = await sut2.tabs
        let restoredActive = await sut2.activeTabId
        XCTAssertEqual(restoredTabs.map(\.id), [tab1.id, tab2.id])
        XCTAssertEqual(restoredActive, tab2.id)
    }

    // MARK: - watcher registration + cancellation

    func test_registerWatcher_cancelWatcher() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let tab = makeOverview()
        await sut.openTab(tab)

        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(60))
        }
        await sut.registerWatcher(for: tab.id, task: task)
        XCTAssertFalse(task.isCancelled)

        await sut.cancelWatcher(for: tab.id)
        XCTAssertTrue(task.isCancelled)
    }

    // MARK: - stateStream emits on mutations

    func test_stateStream_emitsSnapshotOnOpen() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let stream = await sut.stateStream()
        var iter = stream.makeAsyncIterator()

        // Initial empty snapshot.
        let initial = await iter.next()
        XCTAssertEqual(initial?.tabs.count, 0)

        // Open a tab — should trigger a second emission.
        let tab = makeOverview()
        await sut.openTab(tab)

        let afterOpen = await iter.next()
        XCTAssertEqual(afterOpen?.tabs.count, 1)
        XCTAssertEqual(afterOpen?.activeTabId, tab.id)
    }
}
