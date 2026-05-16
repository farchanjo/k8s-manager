// Tests/AppShellTests/TopRightChromeViewModelTests.swift
// Coverage: TopRightChromeViewModel state transitions + notification stream ingestion.

import XCTest
@testable import AppShell

// MARK: - TopRightChromeViewModelTests

@MainActor
final class TopRightChromeViewModelTests: XCTestCase {

    // MARK: toggleAssistant

    func test_toggleAssistant_opensPanel() {
        let sut = TopRightChromeViewModel()
        XCTAssertFalse(sut.assistantPanelOpen)
        sut.toggleAssistant()
        XCTAssertTrue(sut.assistantPanelOpen)
    }

    func test_toggleAssistant_closesPanel() {
        let sut = TopRightChromeViewModel()
        sut.toggleAssistant()
        sut.toggleAssistant()
        XCTAssertFalse(sut.assistantPanelOpen)
    }

    func test_toggleAssistant_closesNotificationsIfOpen() {
        let sut = TopRightChromeViewModel()
        sut.toggleNotifications()
        XCTAssertTrue(sut.notificationsOpen)
        sut.toggleAssistant()
        XCTAssertTrue(sut.assistantPanelOpen)
        XCTAssertFalse(sut.notificationsOpen)
    }

    // MARK: toggleNotifications

    func test_toggleNotifications_opensPopover() {
        let sut = TopRightChromeViewModel()
        XCTAssertFalse(sut.notificationsOpen)
        sut.toggleNotifications()
        XCTAssertTrue(sut.notificationsOpen)
    }

    func test_toggleNotifications_closesPopover() {
        let sut = TopRightChromeViewModel()
        sut.toggleNotifications()
        sut.toggleNotifications()
        XCTAssertFalse(sut.notificationsOpen)
    }

    // MARK: start — toast stream subscription

    func test_start_ingestsNewToastsFromViewModel() async throws {
        let sut = TopRightChromeViewModel()
        let toastVM = ToastStackViewModel()

        let task = Task {
            await sut.start(observing: toastVM)
        }
        defer { task.cancel() }

        // Enqueue an error toast — should become a NotificationEntry.
        toastVM.enqueue(
            ToastCard(
                title: "Pod CrashLoopBackOff",
                message: "nginx-c9rv8 in connectors",
                severity: .error
            )
        )

        // Allow one polling cycle (≥1 s).
        try await Task.sleep(for: .seconds(1), tolerance: .seconds(0.5))

        XCTAssertEqual(sut.notifications.count, 1)
        XCTAssertEqual(sut.notifications.first?.title, "Pod CrashLoopBackOff")
        XCTAssertEqual(sut.notifications.first?.severity, .error)
    }

    func test_start_incrementsUnreadCount() async throws {
        let sut = TopRightChromeViewModel()
        let toastVM = ToastStackViewModel()

        let task = Task {
            await sut.start(observing: toastVM)
        }
        defer { task.cancel() }

        toastVM.enqueue(ToastCard(title: "Alpha", severity: .info))
        toastVM.enqueue(ToastCard(title: "Beta",  severity: .warning))

        try await Task.sleep(for: .seconds(1), tolerance: .seconds(0.5))

        XCTAssertEqual(sut.unreadNotificationCount, 2)
    }

    // MARK: markAllRead

    func test_markAllRead_resetsUnreadCount() async throws {
        let sut = TopRightChromeViewModel()
        let toastVM = ToastStackViewModel()

        let task = Task {
            await sut.start(observing: toastVM)
        }
        defer { task.cancel() }

        toastVM.enqueue(ToastCard(title: "Cluster reconnected", severity: .success))
        try await Task.sleep(for: .seconds(1), tolerance: .seconds(0.5))

        XCTAssertGreaterThan(sut.unreadNotificationCount, 0)
        sut.markAllRead()
        XCTAssertEqual(sut.unreadNotificationCount, 0)
    }

    // MARK: clearAll

    func test_clearAll_removesAllNotifications() async throws {
        let sut = TopRightChromeViewModel()
        let toastVM = ToastStackViewModel()

        let task = Task {
            await sut.start(observing: toastVM)
        }
        defer { task.cancel() }

        toastVM.enqueue(ToastCard(title: "Gamma", severity: .neutral))
        try await Task.sleep(for: .seconds(1), tolerance: .seconds(0.5))

        sut.clearAll()
        XCTAssertTrue(sut.notifications.isEmpty)
        XCTAssertEqual(sut.unreadNotificationCount, 0)
    }
}

// MARK: - NotificationSeverity mapping tests

@MainActor
final class NotificationSeverityTests: XCTestCase {

    func test_systemImages_areNonEmpty() {
        for severity in NotificationSeverity.allCases {
            XCTAssertFalse(severity.systemImage.isEmpty, "systemImage empty for \(severity)")
        }
    }

    func test_notificationEntry_markingRead() {
        let entry = NotificationEntry(
            severity: .error,
            title: "Test",
            timestampRFC3339: "2026-05-16T00:00:00Z"
        )
        XCTAssertFalse(entry.isRead)
        let read = entry.markingRead()
        XCTAssertTrue(read.isRead)
        // Original is unchanged (value type copy-on-write).
        XCTAssertFalse(entry.isRead)
    }
}
