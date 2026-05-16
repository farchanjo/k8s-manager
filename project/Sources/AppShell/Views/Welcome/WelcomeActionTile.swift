// Views/Welcome/WelcomeActionTile.swift — app_shell bounded context
// DDD role: View — single Welcome tab action tile
// ADR ref: ADR-0054 (Welcome tab and cluster-acquisition entry surface)

import SwiftUI

// MARK: - WelcomeActionTile

/// Renders a single action tile in the Welcome tab two-column grid.
///
/// The tile is a keyboard-focusable button with an SF Symbol leading icon, a
/// title, and a one-line description. Hover and focus produce visual
/// feedback consistent with the rest of the app shell.
struct WelcomeActionTile: View {

    let action: WelcomeAction
    let onInvoke: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onInvoke) {
            HStack(alignment: .top, spacing: 14) {
                iconBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(action.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(tileBackground)
            .overlay(tileBorder)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
    }

    // MARK: Sub-views

    private var iconBadge: some View {
        Image(systemName: action.systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.tint.opacity(0.12))
            )
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
    }
}
