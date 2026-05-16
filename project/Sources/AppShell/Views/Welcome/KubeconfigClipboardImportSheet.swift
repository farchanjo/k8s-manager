// Views/Welcome/KubeconfigClipboardImportSheet.swift — app_shell bounded context
// DDD role: View — clipboard kubeconfig import sheet
// ADR ref: ADR-0056 (kubeconfig import from clipboard)

import SwiftUI

// MARK: - KubeconfigClipboardImportSheet

/// Modal sheet (attached to the main window) presented when the operator
/// chooses "Add Kubeconfig from Clipboard" on the Welcome tab (ADR-0056).
///
/// Three content zones per ADR-0056 § "Validation sheet UI shape":
/// - Header: title + description.
/// - Content area: empty-clipboard / error / summary.
/// - Footer: Paste / Cancel / Import buttons.
///
/// The view is keyboard-navigable: Tab moves between buttons; Return
/// activates the focused button; Escape is equivalent to Cancel.
public struct KubeconfigClipboardImportSheet: View {

    @State private var viewModel: KubeconfigClipboardImportViewModel
    @Environment(\.dismiss) private var dismiss

    /// Designated initialiser.
    ///
    /// - Parameter viewModel: Observable view model wired to the real
    ///   `KubeconfigLoaderPort` adapter and import handler.
    public init(viewModel: KubeconfigClipboardImportViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentArea
                .frame(minHeight: 200, idealHeight: 280)
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 580, maxWidth: 640)
        .onAppear {
            viewModel.pasteFromClipboard()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Import kubeconfig from clipboard")
                .font(.headline)
            Text("Paste a kubeconfig YAML blob from Slack, email, or any other source.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: Content area

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.state {
        case .idle, .parsing:
            ProgressView("Reading clipboard…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

        case .emptyClipboard:
            ContentUnavailableView(
                "Clipboard is empty",
                systemImage: "doc.on.clipboard",
                description: Text("Copy a kubeconfig YAML and press \"Paste from Clipboard\".")
            )
            .padding()

        case .invalid(let violations):
            VStack(alignment: .leading, spacing: 8) {
                Text("Validation errors")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                ForEach(Array(violations.enumerated()), id: \.offset) { _, v in
                    Label(v, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

        case .valid(let summary):
            ValidSummaryView(summary: summary)
                .padding()

        case .importing:
            ProgressView("Importing clusters…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

        case .imported(let count):
            ContentUnavailableView(
                "\(count) cluster(s) added",
                systemImage: "checkmark.circle.fill",
                description: Text("The new clusters are now visible in the cluster strip.")
            )
            .symbolRenderingMode(.multicolor)
            .padding()

        case .importFailed(let detail):
            VStack(alignment: .leading, spacing: 8) {
                Label("Import failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Paste from Clipboard") {
                viewModel.pasteFromClipboard()
            }
            .disabled(isPasteDisabled)
            .keyboardShortcut("v", modifiers: [.command])

            Spacer()

            Button("Cancel", role: .cancel) {
                viewModel.cancel()
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Import") {
                viewModel.confirmImport()
                if case .imported = viewModel.state { dismiss() }
            }
            .disabled(!isImportEnabled)
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Button state helpers

    private var isPasteDisabled: Bool {
        switch viewModel.state {
        case .parsing, .importing: return true
        case .imported:            return true
        default:                   return false
        }
    }

    private var isImportEnabled: Bool {
        if case .valid = viewModel.state { return true }
        return false
    }
}

// MARK: - ValidSummaryView

private struct ValidSummaryView: View {

    let summary: ImportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ready to import", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Clusters").foregroundStyle(.secondary)
                    Text("\(summary.clusterCount)")
                }
                GridRow {
                    Text("Contexts").foregroundStyle(.secondary)
                    Text("\(summary.contextCount)")
                }
                if let current = summary.currentContext {
                    GridRow {
                        Text("Current context").foregroundStyle(.secondary)
                        Text(current).lineLimit(1)
                    }
                }
            }
            .font(.callout)

            if !summary.providerHints.isEmpty {
                Divider()
                Text("Detected providers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(summary.providerHints.sorted(by: { $0.key < $1.key })), id: \.key) { ctx, provider in
                    HStack {
                        Text(ctx)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(provider)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
