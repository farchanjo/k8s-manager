// Views/Editor/YAMLEditorToolbar.swift — app_shell bounded context
// DDD role: View — sticky toolbar for the YAML editor tab (Onda 3)
// ADR ref: ADR-0030 (integrated editor UX), ADR-0023 (keyboard shortcuts)

import SwiftUI

// MARK: - YAMLEditorToolbar

/// Sticky top bar for `YAMLEditorTab`.
///
/// Displays the resource title, namespace badge, dirty indicator, and
/// action buttons (dry-run toggle, Save ⌘S, Revert, Close ✕).
public struct YAMLEditorToolbar: View {

    // MARK: Input

    let resourceTitle: String
    let namespace: String
    let isDirty: Bool
    let isApplying: Bool
    let onSave: () -> Void
    let onRevert: () -> Void
    let onClose: () -> Void
    let onToggleDryRun: () -> Void

    public init(
        resourceTitle: String,
        namespace: String,
        isDirty: Bool,
        isApplying: Bool,
        onSave: @escaping () -> Void,
        onRevert: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onToggleDryRun: @escaping () -> Void = {}
    ) {
        self.resourceTitle = resourceTitle
        self.namespace = namespace
        self.isDirty = isDirty
        self.isApplying = isApplying
        self.onSave = onSave
        self.onRevert = onRevert
        self.onClose = onClose
        self.onToggleDryRun = onToggleDryRun
    }

    // MARK: Body

    public var body: some View {
        HStack(spacing: 8) {
            titleSection
            Spacer()
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Material.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: Private views

    private var titleSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.outline")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(resourceTitle)
                .font(.headline)
                .lineLimit(1)

            namespaceBadge

            if isDirty {
                dirtyIndicator
            }
        }
    }

    private var namespaceBadge: some View {
        Text(namespace)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(Capsule())
            .foregroundStyle(Color.accentColor)
    }

    private var dirtyIndicator: some View {
        Text("modified")
            .font(.caption2)
            .foregroundStyle(.orange)
            .accessibilityLabel("Unsaved changes")
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            dryRunToggleButton
            revertButton
            saveButton
            Divider().frame(height: 16)
            closeButton
        }
    }

    private var dryRunToggleButton: some View {
        Button(action: onToggleDryRun) {
            Label("Dry Run", systemImage: "doc.badge.clock")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .help("Toggle dry-run preview panel")
        .accessibilityLabel("Toggle dry-run preview")
    }

    private var revertButton: some View {
        Button(action: onRevert) {
            Label("Revert", systemImage: "arrow.uturn.backward")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .disabled(!isDirty || isApplying)
        .help("Revert to last loaded state")
        .accessibilityLabel("Revert changes")
    }

    private var saveButton: some View {
        Button(action: onSave) {
            if isApplying {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isDirty || isApplying)
        .keyboardShortcut("s", modifiers: .command)
        .help("Apply changes to cluster (⌘S)")
        .accessibilityLabel(isApplying ? "Applying…" : "Save changes")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .imageScale(.small)
        }
        .buttonStyle(.plain)
        .help("Close editor tab")
        .accessibilityLabel("Close editor")
    }
}
