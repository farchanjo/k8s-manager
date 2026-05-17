// Views/Chrome/AssistantToggleButton.swift — app_shell bounded context
// DDD role: Leaf view — assistant panel toggle chrome button
// ADR ref: ADR-0051 (top-right chrome), ADR-0074 (Change A — icon-only style)

import SwiftUI

// MARK: - AssistantToggleButton

/// 28 × 28 chrome button that toggles the assistant slide-out panel.
///
/// Icon-only sparkles button matching the uniform icon style of bell and avatar
/// buttons per ADR-0074 Change A. Active state uses `Color.accentColor`
/// foreground; inactive uses `Color.secondary`. No background fill.
///
/// Tooltip: "Toggle Assistant (⌘\)"
@MainActor
public struct AssistantToggleButton: View {

    let isOpen: Bool
    let action: @MainActor () -> Void

    public init(isOpen: Bool, action: @escaping @MainActor () -> Void) {
        self.isOpen = isOpen
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .help("Toggle Assistant (⌘\\)")
        .accessibilityLabel(isOpen ? "Close Assistant panel" : "Open Assistant panel")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Private

    private var label: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isOpen ? Color.accentColor : Color.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
}
