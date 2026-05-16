// Tests/AppShellTests/Domain/CommandPaletteAggregateTests.swift
// Target: AppShellTests
// Coverage: CommandPaletteAggregate state transitions

import XCTest
@testable import AppShell

final class CommandPaletteAggregateTests: XCTestCase {

    private func makeSUT(id: String = "00000000-0000-7000-8000-000000000001") -> CommandPaletteAggregate {
        let initial = CommandPalette(id: id)
        return CommandPaletteAggregate(initial: initial)
    }

    // MARK: - Open / Close

    func test_open_setsIsOpenTrue_andResetsQueryAndCursor() async {
        let sut = makeSUT()
        await sut.updateQuery("pods")
        await sut.moveCursor(by: 2, resultCount: 5)
        await sut.open()

        let state = await sut.current
        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.query, "")
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_close_setsIsOpenFalse() async {
        let sut = makeSUT()
        await sut.open()
        await sut.close()

        let state = await sut.current
        XCTAssertFalse(state.isOpen)
    }

    // MARK: - Query updates

    func test_updateQuery_setsQueryAndResetsCursor() async {
        let sut = makeSUT()
        await sut.open()
        await sut.moveCursor(by: 3, resultCount: 10)
        await sut.updateQuery("dep")

        let state = await sut.current
        XCTAssertEqual(state.query, "dep")
        XCTAssertEqual(state.selectedIndex, 0)
    }

    // MARK: - Cursor navigation

    func test_moveCursor_wrapsForwardAtEnd() async {
        let sut = makeSUT()
        await sut.open()
        // Move to last item (index 4 in list of 5)
        for _ in 0..<5 { await sut.moveCursor(by: 1, resultCount: 5) }
        let state = await sut.current
        // 5 % 5 == 0 → wraps to beginning
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_moveCursor_wrapsBackwardAtStart() async {
        let sut = makeSUT()
        await sut.open()
        await sut.moveCursor(by: -1, resultCount: 5)
        let state = await sut.current
        XCTAssertEqual(state.selectedIndex, 4, "Backward wrap should land at last item")
    }

    func test_moveCursor_noopWhenResultCountZero() async {
        let sut = makeSUT()
        await sut.open()
        await sut.moveCursor(by: 1, resultCount: 0)
        let state = await sut.current
        XCTAssertEqual(state.selectedIndex, 0)
    }

    // MARK: - Recent invocations ring

    func test_recordInvocation_prependsToRing() async {
        let sut = makeSUT()
        await sut.recordInvocation(commandId: "view-logs", durationMillis: 42)

        let state = await sut.current
        XCTAssertEqual(state.recentInvocations.count, 1)
        XCTAssertEqual(state.recentInvocations[0].commandId, "view-logs")
    }

    func test_recordInvocation_evictsOldestWhenRingExceeds50() async {
        let sut = makeSUT()
        for i in 0..<51 {
            await sut.recordInvocation(commandId: "cmd-\(i)", durationMillis: i)
        }

        let state = await sut.current
        XCTAssertEqual(state.recentInvocations.count, 50, "Ring must not exceed 50 entries")
        // Most recent is first
        XCTAssertEqual(state.recentInvocations[0].commandId, "cmd-50")
    }

    func test_hydrateRecents_clampsToFirst50() async {
        let sut = makeSUT()
        let invocations = (0..<60).map { i in
            CommandInvocation(commandId: "cmd-\(i)", invokedAt: "2026-01-01T00:00:00Z", durationMillis: i)
        }
        await sut.hydrateRecents(invocations)

        let state = await sut.current
        XCTAssertEqual(state.recentInvocations.count, 50)
    }

    // MARK: - AsyncStream broadcasting

    func test_stateStream_emitsCurrentStateImmediately() async {
        let sut = makeSUT()
        var received: [CommandPalette] = []
        let stream = await sut.stateStream()
        var iter = stream.makeAsyncIterator()
        if let first = await iter.next() { received.append(first) }

        XCTAssertEqual(received.count, 1)
        XCTAssertFalse(received[0].isOpen)
    }
}
