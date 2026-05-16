// Tests/AppShellTests/ToastStackViewModelTests.swift
// Target: AppShellTests
// ADR ref: ADR-0032 (toast notification system — FIFO drop, queue, dismiss, severity)
// Note: uses `ToastCard` (view-layer model) not `Toast` (domain Codable model).
import XCTest
@testable import AppShell

@MainActor
final class ToastStackViewModelTests: XCTestCase {

    // MARK: Helpers

    private func makeViewModel() -> ToastStackViewModel { ToastStackViewModel() }

    private func makeToast(
        id: UUID = UUID(),
        severity: ToastSeverity = .info,
        pinned: Bool = false
    ) -> ToastCard {
        ToastCard(id: id, title: "Test", severity: severity, pinned: pinned)
    }

    // MARK: Test 1 — enqueue up to capacity

    /// Five toasts enqueue without dropping any.
    func test_enqueue_upToCapacity() {
        let vm = makeViewModel()
        for _ in 0..<5 {
            vm.enqueue(makeToast())
        }
        XCTAssertEqual(vm.activeToasts.count, 5, "Stack must hold exactly 5 toasts at capacity")
    }

    // MARK: Test 2 — FIFO drop of oldest non-pinned on overflow

    /// On the 6th enqueue, the oldest non-pinned toast is evicted (FIFO).
    func test_enqueue_sixthToastFIFODropsOldestNonPinned() {
        let vm = makeViewModel()
        let firstId = UUID()
        vm.enqueue(makeToast(id: firstId, pinned: false))
        for _ in 0..<4 {
            vm.enqueue(makeToast(pinned: false))
        }
        XCTAssertEqual(vm.activeToasts.count, 5)

        let incomingId = UUID()
        vm.enqueue(makeToast(id: incomingId, pinned: false))

        XCTAssertEqual(vm.activeToasts.count, 5, "Capacity must remain 5 after FIFO drop")
        XCTAssertFalse(
            vm.activeToasts.contains(where: { $0.id == firstId }),
            "Oldest non-pinned toast must be evicted"
        )
        XCTAssertTrue(
            vm.activeToasts.contains(where: { $0.id == incomingId }),
            "Incoming toast must appear in the stack"
        )
    }

    // MARK: Test 3 — pinned toasts are NOT dropped; overflow queued

    /// When all 5 active toasts are pinned, a 6th goes to the overflow queue (not evicted).
    func test_enqueue_pinnedToastsNotDroppedGoesToOverflow() {
        let vm = makeViewModel()
        let pinnedIds = (0..<5).map { _ -> UUID in
            let id = UUID()
            vm.enqueue(makeToast(id: id, pinned: true))
            return id
        }
        XCTAssertEqual(vm.activeToasts.count, 5)

        let overflowId = UUID()
        vm.enqueue(makeToast(id: overflowId, pinned: false))

        // All pinned toasts must still be active.
        let activeIds = Set(vm.activeToasts.map(\.id))
        for pid in pinnedIds {
            XCTAssertTrue(activeIds.contains(pid), "Pinned toast \(pid) must not be evicted")
        }
        // Overflow toast must NOT be in active stack yet.
        XCTAssertFalse(activeIds.contains(overflowId), "Overflow toast must not appear in stack while all slots are pinned")
    }

    // MARK: Test 4 — dismiss drains overflow

    /// Dismissing a pinned toast when an overflow item exists drains the queue.
    func test_dismiss_drainsOverflowAfterPinnedDismissed() {
        let vm = makeViewModel()
        let pinnedId = UUID()
        vm.enqueue(makeToast(id: pinnedId, pinned: true))
        for _ in 0..<4 {
            vm.enqueue(makeToast(pinned: true))
        }
        let overflowId = UUID()
        vm.enqueue(makeToast(id: overflowId, pinned: false))
        XCTAssertFalse(vm.activeToasts.contains(where: { $0.id == overflowId }), "Overflow toast must be queued, not active")

        vm.dismiss(id: pinnedId)
        XCTAssertTrue(
            vm.activeToasts.contains(where: { $0.id == overflowId }),
            "Overflow toast must drain into the active stack after a slot opens"
        )
    }
}

// MARK: - Severity auto-dismiss contract

final class ToastSeverityTests: XCTestCase {

    func test_autoDismissMs_matchesADR0032() {
        XCTAssertEqual(ToastSeverity.success.autoDismissMs, 3_000)
        XCTAssertEqual(ToastSeverity.info.autoDismissMs,    3_000)
        XCTAssertEqual(ToastSeverity.warning.autoDismissMs, 5_000)
        XCTAssertEqual(ToastSeverity.error.autoDismissMs,   8_000)
        XCTAssertEqual(ToastSeverity.neutral.autoDismissMs, 4_000)
    }
}
