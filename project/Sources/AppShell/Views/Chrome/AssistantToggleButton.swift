// Views/Chrome/AssistantToggleButton.swift — app_shell bounded context
// DDD role: Leaf view — assistant panel toggle chrome button
// ADR ref: ADR-0051 (top-right chrome)

import SwiftUI

// MARK: - AssistantToggleButton

/// 28 × 28 chrome button that toggles the assistant slide-out panel.
///
/// Displays a sparkles icon and "PRISM AI" label. Active state renders
/// with the accent background and white text; inactive uses secondary fill.
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
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
            Text("PRISM AI")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(isOpen ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var background: some View {
        Group {
            if isOpen {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
            }
        }
    }
}
