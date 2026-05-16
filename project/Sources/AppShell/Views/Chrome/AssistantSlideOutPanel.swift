// Views/Chrome/AssistantSlideOutPanel.swift — app_shell bounded context
// DDD role: Overlay view — assistant chat slide-out panel from the right edge
// ADR ref: ADR-0051 (top-right chrome, detail drawer pattern)

import SwiftUI

// MARK: - AssistantSlideOutPanel

/// Right-edge slide-out panel hosting `AssistantChatView`.
///
/// Width is fixed at 360 pt. Animated with `move(edge: .trailing)` + `.easeInOut(0.25s)`.
/// Placed as an overlay via `ZStack(alignment: .topTrailing)` in the root scene.
///
/// If `AssistantChatView` is not yet wired to a real backend, a placeholder is shown.
@MainActor
public struct AssistantSlideOutPanel: View {

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            panelContent
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Divider()
        }
    }

    // MARK: Private

    private var panelHeader: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("PRISM AI")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var panelContent: some View {
        AssistantChatView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
