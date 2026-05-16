// Views/Editor/ApplyConfirmationSheet.swift — app_shell bounded context
// DDD role: View — ADR-0012 double-confirm modal for destructive YAML mutations (Onda 3)
// ADR ref: ADR-0012 (confirmation requirements, double-confirm with name entry)

import SwiftUI
import SharedKernel

// MARK: - ApplyConfirmationSheet

/// Modal confirmation sheet for the YAML editor apply pipeline.
///
/// Presents the resource ref summary, mutation type chip, destructiveness badge,
/// and — for `DestructivenessLevel.destructive` — a name-entry text field that
/// gates the Apply button.
public struct ApplyConfirmationSheet: View {

    @Bindable var viewModel: YAMLEditorViewModel

    let ref: ResourceRef

    public init(viewModel: YAMLEditorViewModel, ref: ResourceRef) {
        self.viewModel = viewModel
        self.ref = ref
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                resourceSummary
                Divider()
                destructivenessSection
                if viewModel.destructivenessLevel == .destructive {
                    nameConfirmSection
                }
                conflictsSection
                Spacer()
                actionRow
            }
            .padding(24)
            .navigationTitle("Confirm Apply")
            .navigationBarTitleDisplayMode()
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: Private sections

    private var resourceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resource")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ref.kind.kind): \(ref.name)")
                        .font(.headline)
                    if let ns = ref.namespace {
                        Text("Namespace: \(ns)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var destructivenessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Risk Level")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            destructivenessBadge
            if viewModel.destructivenessLevel != .safe {
                Text(destructivenessDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var destructivenessBadge: some View {
        let (label, color, icon) = badgeConfig(for: viewModel.destructivenessLevel)
        return Label(label, systemImage: icon)
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var nameConfirmSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type the resource name to confirm:")
                .font(.caption.bold())
                .foregroundStyle(.red)
            TextField(ref.name, text: $viewModel.confirmationToken)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            if !viewModel.confirmationToken.isEmpty
                && viewModel.confirmationToken != ref.name {
                Text("Name does not match")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var conflictsSection: some View {
        if let result = viewModel.dryRunResult, !result.conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Force ownership over conflicting fields", isOn: $viewModel.forceConflicts)
                    .font(.subheadline)
                if viewModel.forceConflicts {
                    Text("Warning: this will take ownership from other field managers.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                viewModel.confirmingApply = false
            }
            Spacer()
            Button("Apply") {
                Task { await viewModel.confirmAndApply() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    // MARK: Helpers

    private var canApply: Bool {
        switch viewModel.destructivenessLevel {
        case .safe, .warning:
            return true
        case .destructive:
            return viewModel.confirmationToken == ref.name
        }
    }

    private func badgeConfig(for level: DestructivenessLevel) -> (String, Color, String) {
        switch level {
        case .safe:
            return ("Safe", .green, "checkmark.shield")
        case .warning:
            return ("Warning", .orange, "exclamationmark.triangle")
        case .destructive:
            return ("Destructive", .red, "xmark.shield")
        }
    }

    private var destructivenessDescription: String {
        switch viewModel.destructivenessLevel {
        case .safe:
            return ""
        case .warning:
            return "This operation modifies finalizers or owner references. Proceed with care."
        case .destructive:
            return "This operation removes finalizers, scales to zero, or drops owner references. External resources may be orphaned."
        }
    }
}

// MARK: - NavigationBarTitleDisplayMode workaround for macOS

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayMode() -> some View {
        self
    }
}
