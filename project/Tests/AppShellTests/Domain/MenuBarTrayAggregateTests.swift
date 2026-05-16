// Tests/AppShellTests/Domain/MenuBarTrayAggregateTests.swift
// Target: AppShellTests
// Coverage: MenuBarTrayAggregate state transitions + refresh event application

import XCTest
@testable import AppShell

final class MenuBarTrayAggregateTests: XCTestCase {

    private func makeTray(id: String = "00000000-0000-7000-8000-000000000003") -> MenuBarTray {
        MenuBarTray(id: id)
    }

    private func makeSUT() -> MenuBarTrayAggregate {
        MenuBarTrayAggregate(initial: makeTray())
    }

    // MARK: - Initial state

    func test_initial_defaultsToClosedOnlineActive() async {
        let sut = makeSUT()
        let state = await sut.current
        XCTAssertEqual(state.popoverState, .closed)
        XCTAssertEqual(state.iconState, .online)
        XCTAssertEqual(state.displayMode, .activeCluster)
    }

    // MARK: - Popover state transitions

    func test_setPopoverState_opening_then_open() async {
        let sut = makeSUT()
        await sut.setPopoverState(.opening)
        var state = await sut.current
        XCTAssertEqual(state.popoverState, .opening)

        await sut.setPopoverState(.open)
        state = await sut.current
        XCTAssertEqual(state.popoverState, .open)
    }

    func test_setPopoverState_closingSequence() async {
        let sut = makeSUT()
        await sut.setPopoverState(.open)
        await sut.setPopoverState(.closing)
        await sut.setPopoverState(.closed)

        let state = await sut.current
        XCTAssertEqual(state.popoverState, .closed)
    }

    // MARK: - Refresh event application

    func test_applyRefreshEvent_succeeded_setsOnlineAndTimestamp() async {
        let sut = makeSUT()
        await sut.applyRefreshEvent(.succeeded(durationMillis: 123, widgetCount: 5))

        let state = await sut.current
        XCTAssertEqual(state.iconState, .online)
        XCTAssertNotNil(state.lastRefreshedAtRFC3339)
    }

    func test_applyRefreshEvent_failed_setsDegraded() async {
        let sut = makeSUT()
        await sut.applyRefreshEvent(.failed(widgetId: "cpu-sparkline", reason: "prometheus_unreachable"))

        let state = await sut.current
        XCTAssertEqual(state.iconState, .degraded)
    }

    func test_applyRefreshEvent_recoveryFromDegraded() async {
        let sut = makeSUT()
        await sut.applyRefreshEvent(.failed(widgetId: nil, reason: "rate_limited"))
        await sut.applyRefreshEvent(.succeeded(durationMillis: 200, widgetCount: 4))

        let state = await sut.current
        XCTAssertEqual(state.iconState, .online)
    }

    // MARK: - Preference updates

    func test_updatePreferences_changesDisplayMode() async {
        let sut = makeSUT()
        await sut.updatePreferences(displayMode: .allClustersSummary)

        let state = await sut.current
        XCTAssertEqual(state.displayMode, .allClustersSummary)
    }

    func test_effectiveRefreshInterval_doublesWhenBackgroundAndClosed() async {
        let sut = makeSUT()
        await sut.updatePreferences(
            refreshInterval: .thirty,
            backgroundRefreshEnabled: true
        )

        let state = await sut.current
        XCTAssertEqual(state.popoverState, .closed)
        XCTAssertEqual(state.effectiveRefreshIntervalSeconds, 60)
    }

    func test_effectiveRefreshInterval_normalWhenPopoverOpen() async {
        let sut = makeSUT()
        await sut.updatePreferences(refreshInterval: .fifteen, backgroundRefreshEnabled: true)
        await sut.setPopoverState(.open)

        let state = await sut.current
        XCTAssertEqual(state.effectiveRefreshIntervalSeconds, 15)
    }

    // MARK: - Stream

    func test_stateStream_broadcastsOnMutation() async {
        let sut = makeSUT()
        var received: [MenuBarTray] = []
        let stream = await sut.stateStream()
        var iter = stream.makeAsyncIterator()
        if let first = await iter.next() { received.append(first) }

        await sut.setPopoverState(.open)
        if let second = await iter.next() { received.append(second) }

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0].popoverState, .closed)
        XCTAssertEqual(received[1].popoverState, .open)
    }
}
