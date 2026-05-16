// Tests/AppShellTests/NavigationHistoryTests.swift
// Target: AppShellTests
// Coverage: NavigationHistoryActor — push/back/forward/bounded-capacity/clear/persist

import XCTest
@testable import AppShell
import SharedKernel

final class NavigationHistoryTests: XCTestCase {

    // MARK: Helpers

    private func makeActor(tmpDir: URL) -> NavigationHistoryActor {
        NavigationHistoryActor(
            persistenceURL: tmpDir.appendingPathComponent("navigation-history.json")
        )
    }

    private var tmpDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeEntry(
        clusterId: String = "cluster-a",
        tabId: String = "tab-1",
        kind: NavigationEntryKind = .resourceList,
        namespace: String? = "default",
        selectedResourceName: String? = nil,
        drawerSectionAnchor: String? = nil
    ) -> NavigationEntry {
        NavigationEntry(
            clusterId: clusterId,
            tabId: tabId,
            kind: kind,
            namespace: namespace,
            selectedResourceName: selectedResourceName,
            drawerSectionAnchor: drawerSectionAnchor
        )
    }

    // MARK: - Push adds entry and advances cursor

    func test_push_addsEntryAndAdvancesCursor() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let entry = makeEntry()

        await sut.push(entry)

        let entries = await sut.entries
        let cursor = await sut.cursorIndex
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(cursor, 0)
    }

    // MARK: - Push truncates forward chain

    func test_push_afterBack_truncatesForwardChain() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let e1 = makeEntry(selectedResourceName: "pod-1")
        let e2 = makeEntry(selectedResourceName: "pod-2")
        let e3 = makeEntry(selectedResourceName: "pod-3")

        await sut.push(e1)
        await sut.push(e2)
        await sut.push(e3)

        _ = await sut.back()   // cursor at 1
        _ = await sut.back()   // cursor at 0

        let e4 = makeEntry(selectedResourceName: "pod-4")
        await sut.push(e4)

        let entries = await sut.entries
        let cursor = await sut.cursorIndex
        // After push from index 0, e2 and e3 are discarded, e4 appended.
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(cursor, 1)
        XCTAssertEqual(entries[1].selectedResourceName, "pod-4")
    }

    // MARK: - Back moves cursor toward beginning

    func test_back_movesCursorTowardBeginning() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        await sut.push(makeEntry(selectedResourceName: "a"))
        await sut.push(makeEntry(selectedResourceName: "b"))

        let result = await sut.back()

        let cursor = await sut.cursorIndex
        XCTAssertEqual(cursor, 0)
        XCTAssertEqual(result?.selectedResourceName, "a")
    }

    // MARK: - Back at index 0 returns nil

    func test_back_atFirstEntry_returnsNil() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        await sut.push(makeEntry())

        let result = await sut.back()

        XCTAssertNil(result)
        let cursor = await sut.cursorIndex
        XCTAssertEqual(cursor, 0)
    }

    // MARK: - Forward moves cursor toward end

    func test_forward_movesCursorTowardEnd() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        await sut.push(makeEntry(selectedResourceName: "a"))
        await sut.push(makeEntry(selectedResourceName: "b"))
        _ = await sut.back()    // cursor at 0

        let result = await sut.forward()

        let cursor = await sut.cursorIndex
        XCTAssertEqual(cursor, 1)
        XCTAssertEqual(result?.selectedResourceName, "b")
    }

    // MARK: - Forward at tail returns nil

    func test_forward_atLastEntry_returnsNil() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        await sut.push(makeEntry(selectedResourceName: "a"))

        let result = await sut.forward()

        XCTAssertNil(result)
        let cursor = await sut.cursorIndex
        XCTAssertEqual(cursor, 0)
    }

    // MARK: - Bounded capacity: 101st push evicts oldest entry

    func test_push_exceedingCapacity_evictsOldestEntry() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let limit = NavigationHistoryActor.maxCapacity  // 100

        // Push `limit + 1` distinct entries.
        for index in 0...limit {
            await sut.push(makeEntry(selectedResourceName: "resource-\(index)"))
        }

        let entries = await sut.entries
        let cursor = await sut.cursorIndex
        XCTAssertEqual(entries.count, limit)
        XCTAssertEqual(cursor, limit - 1)
        // Oldest entry ("resource-0") must be gone; newest ("resource-100") must be present.
        XCTAssertFalse(entries.contains { $0.selectedResourceName == "resource-0" })
        XCTAssertEqual(entries.last?.selectedResourceName, "resource-\(limit)")
    }

    // MARK: - Duplicate suppression

    func test_push_duplicateOfCurrent_isSuppressed() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let e1 = makeEntry(selectedResourceName: "pod-x")

        await sut.push(e1)
        // Push an entry with the same stable identity.
        let e1Dup = makeEntry(selectedResourceName: "pod-x")
        await sut.push(e1Dup)

        let entries = await sut.entries
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - Back does not push a new entry

    func test_back_doesNotPushNewEntry() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        await sut.push(makeEntry(selectedResourceName: "a"))
        await sut.push(makeEntry(selectedResourceName: "b"))
        let countBefore = await sut.entries.count

        _ = await sut.back()

        let countAfter = await sut.entries.count
        XCTAssertEqual(countAfter, countBefore)
    }

    // MARK: - Clear resets deque and cursor

    func test_clear_resetsDequeAndCursor() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        await sut.push(makeEntry())
        await sut.push(makeEntry(selectedResourceName: "b"))

        await sut.clear()

        let entries = await sut.entries
        let cursor = await sut.cursorIndex
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(cursor, -1)
    }

    // MARK: - Snapshot reflects back/forward availability

    func test_stateStream_emitsCorrectAvailability() async throws {
        let sut = makeActor(tmpDir: tmpDir)
        let stream = await sut.stateStream()
        var iter = stream.makeAsyncIterator()

        // Initial snapshot — nothing pushed yet.
        let initial = await iter.next()
        XCTAssertEqual(initial?.canGoBack, false)
        XCTAssertEqual(initial?.canGoForward, false)

        // Push two entries.
        await sut.push(makeEntry(selectedResourceName: "a"))
        let afterFirst = await iter.next()
        XCTAssertEqual(afterFirst?.canGoBack, false)
        XCTAssertEqual(afterFirst?.canGoForward, false)

        await sut.push(makeEntry(selectedResourceName: "b"))
        let afterSecond = await iter.next()
        XCTAssertEqual(afterSecond?.canGoBack, true)
        XCTAssertEqual(afterSecond?.canGoForward, false)

        // Go back — forward should now be available.
        _ = await sut.back()
        let afterBack = await iter.next()
        XCTAssertEqual(afterBack?.canGoBack, false)
        XCTAssertEqual(afterBack?.canGoForward, true)
    }

    // MARK: - Persistence: only entries up to cursor are saved

    func test_persist_savesEntriesUpToCursorOnly() async throws {
        let dir = tmpDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sut = makeActor(tmpDir: dir)

        await sut.push(makeEntry(selectedResourceName: "entry-0"))
        await sut.push(makeEntry(selectedResourceName: "entry-1"))
        await sut.push(makeEntry(selectedResourceName: "entry-2"))
        // Move cursor to index 1; entry-2 is the forward chain.
        _ = await sut.back()

        // Allow debounce to fire (> 500 ms).
        try await Task.sleep(for: .milliseconds(700))

        // Load into a fresh actor.
        let sut2 = makeActor(tmpDir: dir)
        try await sut2.loadFromDisk()

        let restored = await sut2.entries
        let cursor = await sut2.cursorIndex
        // Only entries up to cursor (entries 0 and 1) are persisted.
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(cursor, 1)
        XCTAssertEqual(restored[0].selectedResourceName, "entry-0")
        XCTAssertEqual(restored[1].selectedResourceName, "entry-1")
    }

    // MARK: - Cold launch restore capped at 50 entries

    func test_coldLaunch_restoresAtMost50Entries() async throws {
        let dir = tmpDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sut = makeActor(tmpDir: dir)

        // Push 60 distinct entries.
        for index in 0..<60 {
            await sut.push(makeEntry(selectedResourceName: "r-\(index)"))
        }

        try await Task.sleep(for: .milliseconds(700))

        let sut2 = makeActor(tmpDir: dir)
        try await sut2.loadFromDisk()

        let restored = await sut2.entries
        let cursor = await sut2.cursorIndex
        // Feature scenario: persisted 60, restored at most 50 (last 50 entries).
        XCTAssertLessThanOrEqual(restored.count, NavigationHistoryActor.coldLaunchRestoreLimit)
        XCTAssertEqual(cursor, restored.count - 1)
        // Last restored entry must be "r-59".
        XCTAssertEqual(restored.last?.selectedResourceName, "r-59")
    }
}
