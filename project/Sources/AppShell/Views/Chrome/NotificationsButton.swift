// Views/Chrome/NotificationsButton.swift — app_shell bounded context
// DDD role: Leaf view — notifications bell chrome button with badge
// ADR ref: ADR-0051 (top-right chrome)

import SwiftUI

// MARK: - NotificationsButton

/// 24 × 24 bell icon chrome button that opens `NotificationsPopover`.
///
/// Renders a red badge circle with unread count when `unreadCount > 0`.
/// Tooltip: "Notifications"
@MainActor
public struct NotificationsButton: View {

    let unreadCount: Int
    let isOpen: Bool
    let action: @MainActor () -> Void

    public init(
        unreadCount: Int,
        isOpen: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        self.unreadCount = unreadCount
        self.isOpen = isOpen
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                bellIcon
                if unreadCount > 0 { badge }
            }
        }
        .buttonStyle(.plain)
        .help("Notifications")
        .accessibilityLabel(
            unreadCount > 0
                ? "\(unreadCount) unread notifications"
                : "Notifications"
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Private

    private var bellIcon: some View {
        Image(systemName: isOpen ? "bell.fill" : "bell")
            .font(.system(size: 16))
            .foregroundStyle(isOpen ? Color.accentColor : Color.primary)
            .frame(width: 24, height: 24)
    }

    private var badge: some View {
        Text(badgeText)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: 14, minHeight: 14)
            .background(Color.red, in: Capsule())
            .offset(x: 4, y: -4)
    }

    private var badgeText: String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }
}
