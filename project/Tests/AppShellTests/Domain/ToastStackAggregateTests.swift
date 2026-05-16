// Tests/AppShellTests/Domain/ToastStackAggregateTests.swift
// Target: AppShellTests
// Coverage: ToastStackAggregate enqueue / dismiss / pin / overflow

import XCTest
@testable import AppShell

final class ToastStackAggregateTests: XCTestCase {

    private func makeStack(maxConcurrent: Int = 3) -> DomainToastStack {
        DomainToastStack(id: "00000000-0000-7000-8000-000000000002", maxConcurrent: maxConcurrent)
    }

    private func makeSUT(maxConcurrent: Int = 3) -> ToastStackAggregate {
        ToastStackAggregate(initial: makeStack(maxConcurrent: maxConcurrent))
    }

    private func toast(id: String, severity: ToastDomainSeverity = .info, pinned: Bool = false) -> Toast {
        Toast(
            id: id,
            title: "Test \(id)",
            severity: severity,
            emittedAtRFC3339: "2026-05-15T00:00:00Z",
            pinned: pinned
        )
    }

    // MARK: - Enqueue

    func test_enqueue_addsSingleToast() async {
        let sut = makeSUT()
        await sut.enqueue(toast(id: "t1"))

        let state = await sut.current
        XCTAssertEqual(state.activeToasts.count, 1)
        XCTAssertEqual(state.activeToasts[0].id, "t1")
    }

    func test_enqueue_newestFirst() async {
        let sut = makeSUT()
        await sut.enqueue(toast(id: "t1"))
        await sut.enqueue(toast(id: "t2"))

        let state = await sut.current
        XCTAssertEqual(state.activeToasts[0].id, "t2")
        XCTAssertEqual(state.activeToasts[1].id, "t1")
    }

    func test_enqueue_evictsOldestUnpinnedWhenAtCapacity() async {
        let sut = makeSUT(maxConcurrent: 2)
        await sut.enqueue(toast(id: "old"))
        await sut.enqueue(toast(id: "mid"))
        await sut.enqueue(toast(id: "new"))

        let state = await sut.current
        XCTAssertEqual(state.activeToasts.count, 2)
        XCTAssertFalse(state.activeToasts.contains { $0.id == "old" })
    }

    func test_enqueue_queuesWhenAllPinned() async {
        let sut = makeSUT(maxConcurrent: 2)
        await sut.enqueue(toast(id: "p1", pinned: true))
        await sut.enqueue(toast(id: "p2", pinned: true))
        await sut.enqueue(toast(id: "overflow"))

        let state = await sut.current
        XCTAssertEqual(state.activeToasts.count, 2)
        XCTAssertEqual(state.queue.count, 1)
        XCTAssertEqual(state.queue[0].id, "overflow")
    }

    // MARK: - Dismiss

    func test_dismiss_removesToastFromActive() async {
        let sut = makeSUT()
        await sut.enqueue(toast(id: "t1"))
        await sut.dismiss(id: "t1")

        let state = await sut.current
        XCTAssertTrue(state.activeToasts.isEmpty)
    }

    func test_dismiss_promotesQueuedToast() async {
        let sut = makeSUT(maxConcurrent: 1)
        await sut.enqueue(toast(id: "t1"))
        await sut.enqueue(toast(id: "t2"))  // goes to queue

        let before = await sut.current
        XCTAssertEqual(before.queue.count, 1)

        await sut.dismiss(id: "t1")

        let after = await sut.current
        XCTAssertEqual(after.activeToasts.count, 1)
        XCTAssertEqual(after.activeToasts[0].id, "t2")
        XCTAssertTrue(after.queue.isEmpty)
    }

    // MARK: - autoDismissMs severity mapping

    func test_toastSeverity_autoDismissMs() {
        XCTAssertEqual(ToastDomainSeverity.success.autoDismissMs, 3_000)
        XCTAssertEqual(ToastDomainSeverity.info.autoDismissMs, 3_000)
        XCTAssertEqual(ToastDomainSeverity.neutral.autoDismissMs, 4_000)
        XCTAssertEqual(ToastDomainSeverity.warning.autoDismissMs, 5_000)
        XCTAssertEqual(ToastDomainSeverity.error.autoDismissMs, 8_000)
    }

    // MARK: - Pin / Unpin

    func test_setPin_updatesActivateToast() async {
        let sut = makeSUT()
        await sut.enqueue(toast(id: "t1"))
        await sut.setPin(true, id: "t1")

        let state = await sut.current
        XCTAssertTrue(state.activeToasts[0].pinned)
    }

    // MARK: - Stream

    func test_stateStream_emitsInitialState() async {
        let sut = makeSUT()
        let stream: AsyncStream<DomainToastStack> = await sut.stateStream()
        var iter = stream.makeAsyncIterator()
        let first = await iter.next()
        XCTAssertNotNil(first)
        XCTAssertTrue(first!.activeToasts.isEmpty)
    }
}
