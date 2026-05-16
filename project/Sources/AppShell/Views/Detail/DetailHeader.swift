// Views/Detail/DetailHeader.swift — app_shell bounded context
// DDD role: View — sticky action toolbar for the resource detail drawer
// ADR ref: ADR-0021 (detail drawer — Onda 2)

import SwiftUI

// MARK: - DetailHeader

/// Sticky header displayed at the top of `ResourceDetailDrawer`.
///
/// Shows a kind badge, the resource name, five action icon buttons,
/// and a close button. Matches the Lens-inspired header pattern from
/// the wireframe in ADR-0021.
@MainActor
public struct DetailHeader: View {

    // MARK: Input

    /// Human-readable Kubernetes kind (e.g. `"Pod"`, `"Deployment"`).
    public let kind: String
    /// Resource name (e.g. `"nginx-c9rv8"`).
    public let title: String
    /// Tapped when the user wants to open the YAML editor.
    public let onEdit: () -> Void
    /// Tapped when the user wants to open a shell/exec tab.
    public let onShell: () -> Void
    /// Tapped when the user wants to restart the resource.
    public let onRestart: () -> Void
    /// Tapped when the user wants to delete the resource.
    public let onDelete: () -> Void
    /// Tapped when the user wants to close the drawer.
    public let onClose: () -> Void

    // MARK: Init

    public init(
        kind: String,
        title: String,
        onEdit: @escaping () -> Void,
        onShell: @escaping () -> Void,
        onRestart: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.kind = kind
        self.title = title
        self.onEdit = onEdit
        self.onShell = onShell
        self.onRestart = onRestart
        self.onDelete = onDelete
        self.onClose = onClose
    }

    // MARK: Body

    public var body: some View {
        HStack(spacing: 8) {
            kindBadge
            titleLabel
            Spacer()
            actionButtons
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: Private views

    private var kindBadge: some View {
        Text(kind)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            iconButton("pencil", tooltip: "Edit YAML", action: onEdit)
            iconButton("terminal", tooltip: "Open Shell", action: onShell)
            iconButton("arrow.counterclockwise", tooltip: "Restart", action: onRestart)
            iconButton("trash", tooltip: "Delete", role: .destructive, action: onDelete)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .help("Close")
        .keyboardShortcut(.escape, modifiers: [])
    }

    @ViewBuilder
    private func iconButton(
        _ systemName: String,
        tooltip: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .help(tooltip)
    }
}
