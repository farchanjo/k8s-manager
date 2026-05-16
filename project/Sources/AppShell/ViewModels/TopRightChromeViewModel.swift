// ViewModels/TopRightChromeViewModel.swift — app_shell bounded context
// DDD role: ViewModel for the top-right chrome (assistant toggle, notifications, user menu)
// ADR ref: ADR-0051 (top-right chrome area), ADR-0034 (state-driven realtime UI)

import Foundation
import SwiftUI

// MARK: - NotificationSeverity

/// Severity level for a `NotificationEntry`, aligned with `ToastDomainSeverity` naming.
public enum NotificationSeverity: String, Sendable, Hashable, CaseIterable {
    case info, warning, error, success

    /// SF Symbol name per severity.
    public var systemImage: String {
        switch self {
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    /// Semantic color per severity.
    public var color: Color {
        switch self {
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        case .success: return .green
        }
    }
}

// MARK: - NotificationEntry

/// Immutable notification entry stored in `TopRightChromeViewModel`.
///
/// Derived from `ToastCard` events emitted by the toast subsystem.
/// `timestampRFC3339` is stored as a `String` so the type stays fully `Sendable`
/// without importing `Foundation.Date` into callers that need only the display string.
public struct NotificationEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let severity: NotificationSeverity
    public let title: String
    public let subtitle: String?
    public let timestampRFC3339: String
    public private(set) var isRead: Bool

    public init(
        id: UUID = UUID(),
        severity: NotificationSeverity,
        title: String,
        subtitle: String? = nil,
        timestampRFC3339: String,
        isRead: Bool = false
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.subtitle = subtitle
        self.timestampRFC3339 = timestampRFC3339
        self.isRead = isRead
    }

    /// Returns a copy marked as read.
    public func markingRead() -> NotificationEntry {
        var copy = self
        copy.isRead = true
        return copy
    }
}

// MARK: - TopRightChromeViewModel

/// `@Observable` + `@MainActor` view model driving the top-right chrome area.
///
/// Owns:
/// - Assistant slide-out panel open/close state.
/// - Notifications list (last 50 entries, derived from the `ToastStackViewModel` stream).
/// - Unread count badge.
/// - User initials (hardcoded "FA"; will be driven by preferences in a future round).
///
/// Subscribes to `ToastStackViewModel` by polling `activeToasts` changes via a structured
/// `Task` started in `start()`. Caller must call `start()` inside a `.task {}` modifier.
@Observable
@MainActor
public final class TopRightChromeViewModel {

    // MARK: Public state

    /// Whether the assistant slide-out panel is currently visible.
    public var assistantPanelOpen: Bool = false

    /// Whether the notifications popover is currently open.
    public var notificationsOpen: Bool = false

    /// Count of unread notification entries. Drives the badge on `NotificationsButton`.
    public var unreadNotificationCount: Int = 0

    /// Last 50 notification entries, newest first.
    public var notifications: [NotificationEntry] = []

    /// User initials displayed in `UserMenuButton`. Driven by preferences in future.
    public var userInitials: String = "FA"

    // MARK: Private

    private static let maxNotifications = 50
    private var toastViewModel: ToastStackViewModel?
    private var seenToastIds: Set<UUID> = []

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Toggles the assistant slide-out panel. Closes notifications if open.
    public func toggleAssistant() {
        assistantPanelOpen.toggle()
        if assistantPanelOpen { notificationsOpen = false }
    }

    /// Toggles the notifications popover. Closes assistant panel if open.
    public func toggleNotifications() {
        notificationsOpen.toggle()
        if notificationsOpen { assistantPanelOpen = false }
    }

    /// Posts `.k8sManagerShowUserMenu` so the owning view can respond with a sheet.
    public func showUserMenu() {
        NotificationCenter.default.post(name: .k8sManagerShowUserMenu, object: nil)
    }

    /// Marks all notifications as read and resets the badge count.
    public func markAllRead() {
        notifications = notifications.map { $0.markingRead() }
        unreadNotificationCount = 0
    }

    /// Clears all notifications and resets state.
    public func clearAll() {
        notifications = []
        unreadNotificationCount = 0
        seenToastIds = []
    }

    // MARK: Stream subscription

    /// Subscribes to `toastViewModel` state changes and converts new toasts to
    /// `NotificationEntry` values.
    ///
    /// Must be called from a `.task {}` modifier on the owning view so SwiftUI
    /// manages the `Task` lifecycle (cancellation on disappear).
    ///
    /// - Parameter toastViewModel: The shared `ToastStackViewModel` to observe.
    public func start(observing toastViewModel: ToastStackViewModel) async {
        self.toastViewModel = toastViewModel
        // Poll via withObservationTracking to react to @Observable changes.
        await observeToastChanges(toastViewModel)
    }

    // MARK: Private helpers

    private func observeToastChanges(_ vm: ToastStackViewModel) async {
        while !Task.isCancelled {
            let snapshot = vm.activeToasts
            ingestToasts(snapshot)
            // Yield so observation can re-arm; poll at ~1 s to catch rapid bursts.
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func ingestToasts(_ toasts: [ToastCard]) {
        var added = 0
        for toast in toasts where !seenToastIds.contains(toast.id) {
            seenToastIds.insert(toast.id)
            let entry = NotificationEntry(
                id: toast.id,
                severity: mapSeverity(toast.severity),
                title: toast.title,
                subtitle: toast.message,
                timestampRFC3339: ISO8601DateFormatter().string(from: toast.emittedAt)
            )
            notifications.insert(entry, at: 0)
            added += 1
        }
        trimToCapacity()
        if added > 0 { unreadNotificationCount += added }
    }

    private func trimToCapacity() {
        if notifications.count > Self.maxNotifications {
            notifications = Array(notifications.prefix(Self.maxNotifications))
        }
    }

    private func mapSeverity(_ severity: ToastSeverity) -> NotificationSeverity {
        switch severity {
        case .success: return .success
        case .info:    return .info
        case .warning: return .warning
        case .error:   return .error
        case .neutral: return .info
        }
    }
}

// MARK: - Notification.Name extensions

public extension Notification.Name {
    /// Posted by `TopRightChromeViewModel.showUserMenu()`.
    static let k8sManagerShowUserMenu = Notification.Name("appShell.showUserMenu")
    /// Posted when ⌘\\ is pressed — toggles the assistant slide-out panel.
    static let k8sManagerToggleAssistant = Notification.Name("appShell.toggleAssistant")
    /// Posted when ⌘N is pressed — toggles the notifications dropdown.
    static let k8sManagerToggleNotifications = Notification.Name("appShell.toggleNotifications")
}
