// Views/Chrome/UserMenuButton.swift — app_shell bounded context
// DDD role: Leaf view — user initials circle chrome button
// ADR ref: ADR-0051 (top-right chrome)

import SwiftUI

// MARK: - UserMenuButton

/// 28 × 28 circle button showing the user's initials.
///
/// Tapping posts `.k8sManagerShowUserMenu` so the owning view can open
/// a `UserMenuPopover`. Tooltip: "Account & Settings"
@MainActor
public struct UserMenuButton: View {

    let initials: String
    let action: @MainActor () -> Void

    public init(initials: String, action: @escaping @MainActor () -> Void) {
        self.initials = initials
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .help("Account & Settings")
        .accessibilityLabel("User menu — \(initials)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Private

    private var label: some View {
        Text(initials.prefix(2).uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Color.accentColor, in: Circle())
    }
}

// MARK: - UserMenuPopover

/// Popover anchored to `UserMenuButton` with account and application actions.
@MainActor
public struct UserMenuPopover: View {

    let onDismiss: @MainActor () -> Void

    public init(onDismiss: @escaping @MainActor () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuItem("Preferences", symbol: "gearshape", shortcut: "⌘,") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
                onDismiss()
            }
            menuItem("Diagnostics", symbol: "stethoscope") {
                NotificationCenter.default.post(name: .k8sManagerShowDiagnostics, object: nil)
                onDismiss()
            }
            Divider().padding(.vertical, 4)
            menuItem("About K8sManager", symbol: "info.circle") {
                NSApp.orderFrontStandardAboutPanel(nil)
                onDismiss()
            }
            Divider().padding(.vertical, 4)
            menuItem("Quit", symbol: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 200)
    }

    // MARK: Private

    private func menuItem(
        _ label: String,
        symbol: String,
        shortcut: String? = nil,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .frame(width: 16)
                Text(label)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel(label)
    }
}

// MARK: - Notification.Name extension

public extension Notification.Name {
    /// Posted when the user taps Diagnostics in the user menu.
    static let k8sManagerShowDiagnostics = Notification.Name("appShell.showDiagnostics")
}
