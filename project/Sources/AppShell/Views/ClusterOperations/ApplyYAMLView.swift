// Views/ClusterOperations/ApplyYAMLView.swift — app_shell bounded context
// DDD role: View — kubectl apply -f - equivalent with CodeEditor
// ADR ref: ADR-0050 (cluster operations, Onda 2), ADR-0030 (CodeEditor adapter)

import SwiftUI
import SharedKernel

// MARK: - ApplyYAMLView

/// YAML/JSON apply tool — pastes, validates, and SSA-applies a manifest.
///
/// Toolbar: namespace override field + "Dry Run" toggle + "Apply" button.
/// Main area: CodeEditor (YAML syntax).
/// Bottom panel: dry-run diff preview when toggle is on.
/// Drop zone: file drop populates the editor.
public struct ApplyYAMLView: View {

    /// The cluster to target.
    public let clusterId: ClusterId

    @State private var viewModel = ApplyYAMLViewModel()
    @Environment(\.appShellDependencies) private var deps

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        VStack(spacing: 0) {
            applyToolbar
            Divider()
            editorArea
            if viewModel.dryRun, let diff = viewModel.applyState.value?.managedFieldsDiff {
                Divider()
                dryRunPreview(diff: diff)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            Task { await viewModel.dropFile(at: first) }
            return true
        }
    }

    // MARK: Toolbar

    private var applyToolbar: some View {
        HStack(spacing: 12) {
            namespaceOverrideField
            Spacer()
            dryRunToggle
            applyButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var namespaceOverrideField: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.gear")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField(
                "Namespace override",
                text: Binding(
                    get: { viewModel.namespaceOverride ?? "" },
                    set: { viewModel.namespaceOverride = $0.isEmpty ? nil : $0 }
                )
            )
            .textFieldStyle(.plain)
            .font(.callout)
            .frame(width: 160)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var dryRunToggle: some View {
        Toggle("Dry Run", isOn: $viewModel.dryRun)
            .toggleStyle(.checkbox)
            .font(.callout)
            .help("Preview changes without applying to the cluster")
    }

    private var applyButton: some View {
        Button(viewModel.dryRun ? "Dry Run" : "Apply") {
            Task { await viewModel.apply(clusterId: clusterId) }
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.dryRun ? .blue : .green)
        .disabled(viewModel.applyState.isLoading || viewModel.yamlText.isEmpty)
        .keyboardShortcut(.return, modifiers: [.command])
    }

    // MARK: Editor area

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            editorBody
            if viewModel.applyState.isLoading {
                applyOverlay
            }
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        PlainTextEditorBridge(
            text: $viewModel.yamlText,
            language: .yaml,
            codeEditor: deps.codeEditor
        )
    }

    private var fallbackEditor: some View {
        TextEditor(text: $viewModel.yamlText)
            .font(.system(.body, design: .monospaced))
            .onChange(of: viewModel.yamlText) { _, _ in
                Task { await viewModel.validate() }
            }
    }

    private var applyOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(viewModel.dryRun ? "Running dry-run…" : "Applying…")
                .font(.callout)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding()
    }

    // MARK: Validation errors

    @ViewBuilder
    private var validationErrorBanner: some View {
        let errors = viewModel.validationErrors.filter { $0.severity == .error }
        if !errors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(errors) { err in
                    Label("Line \(err.line): \(err.message)", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: Dry-run preview

    private func dryRunPreview(diff: String) -> some View {
        ScrollView {
            Text(diff)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(height: 180)
        .background(.quinary)
    }
}

// MARK: - PlainTextEditorBridge

/// Thin SwiftUI bridge to `CodeEditorPort` that keeps `body` under 30 lines.
private struct PlainTextEditorBridge: View {
    @Binding var text: String
    let language: EditorLanguage
    let codeEditor: any CodeEditorPort

    var body: some View {
        codeEditor.makeEditor(initial: text, language: language, theme: .system)
    }
}

// `codeEditor` shim removed — AppShellDependencies now carries `codeEditor`
// natively (Onda 3 composition-root wiring). Fallback editor unused; the
// adapter port is always available, falling through to UnimplementedCodeEditor
// in previews/tests if not injected.
