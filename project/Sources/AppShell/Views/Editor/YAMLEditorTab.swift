// Views/Editor/YAMLEditorTab.swift — app_shell bounded context
// DDD role: View — YAML editor tab (Onda 3)
// ADR ref: ADR-0030 (integrated editor — dry-run → SSA → audit)
//           ADR-0012 (mutation policy, confirmation modal)

import SwiftUI
import SharedKernel
import ResourceBrowser

// MARK: - YAMLEditorTab

/// Full YAML editor tab: toolbar + code editor + dry-run preview + validation pane.
///
/// Flow: operator opens tab from a list view → `start()` bootstraps the VM →
/// editing triggers debounced validation and dry-run → Apply opens
/// `ApplyConfirmationSheet` → on confirm, SSA PATCH + audit entry.
public struct YAMLEditorTab: View {

    // MARK: Input

    public let clusterId: ClusterId
    public let ref: ResourceRef
    public let initialDraft: String

    // MARK: State

    @State private var viewModel = YAMLEditorViewModel()
    @State private var editorView: AnyView?
    @Environment(\.appShellDependencies) private var deps

    /// Bindable projection of `viewModel` used in sheet / alert modifiers.
    private var bindableVM: Bindable<YAMLEditorViewModel> { Bindable(viewModel) }

    // MARK: Init

    public init(
        clusterId: ClusterId,
        ref: ResourceRef,
        initialDraft: String
    ) {
        self.clusterId = clusterId
        self.ref = ref
        self.initialDraft = initialDraft
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            editorContent
            if !viewModel.validationErrors.isEmpty {
                ValidationErrorPane(
                    errors: viewModel.validationErrors,
                    onJumpToLine: { _ in }
                )
                .frame(maxHeight: 120)
            }
        }
        .task { await bootstrap() }
        .sheet(isPresented: bindableVM.confirmingApply) {
            ApplyConfirmationSheet(viewModel: viewModel, ref: ref)
        }
        .alert("Discard unsaved changes?", isPresented: bindableVM.confirmingDiscard) {
            Button("Discard", role: .destructive) { viewModel.discardAndClose() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Resource Modified Externally", isPresented: bindableVM.externalConflictDetected) {
            Button("Pull Latest") { Task { await reloadFromCluster() } }
            Button("Keep Mine", role: .cancel) { viewModel.externalConflictDetected = false }
        } message: {
            Text("The resource was changed by another actor. Pull the latest version or keep your draft.")
        }
    }

    // MARK: Private views

    private var toolbar: some View {
        YAMLEditorToolbar(
            resourceTitle: "\(ref.kind.kind): \(ref.name)",
            namespace: ref.namespace ?? "(cluster-scoped)",
            isDirty: viewModel.isDirty,
            isApplying: viewModel.isApplying,
            onSave: { Task { await viewModel.requestApply() } },
            onRevert: { viewModel.revert() },
            onClose: { viewModel.requestDiscard() },
            onToggleDryRun: { viewModel.showDryRunPanel.toggle() }
        )
    }

    private var editorContent: some View {
        HSplitView {
            codeEditorRegion
            if viewModel.showDryRunPanel, let result = viewModel.dryRunResult {
                DryRunPreviewPanel(result: result)
                    .frame(minWidth: 280, idealWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var codeEditorRegion: some View {
        Group {
            if let editorView {
                editorView
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Boots the view: mounts the CodeEditor port, starts the view model,
    /// and consumes the port's edit stream to keep `viewModel.draftText` in
    /// sync (replaces the previous SwiftUI `TextEditor` stub).
    /// The concrete adapter (`CodeEditorViewAdapter`) is wired by the
    /// composition root; AppShell consumes only `CodeEditorPort` to honour
    /// the ADR-0020 invariant.
    private func bootstrap() async {
        editorView = deps.codeEditor.makeEditor(
            initial: initialDraft,
            language: .yaml,
            theme: .system
        )
        await viewModel.start(clusterId: clusterId, ref: ref, initialDraft: initialDraft)
        for await event in deps.codeEditor.editStream() {
            viewModel.draftText = event.content
            await viewModel.validate()
            await viewModel.runDryRun()
        }
    }

    // MARK: Private helpers

    private func reloadFromCluster() async {
        viewModel.externalConflictDetected = false
        // Re-fetch the live manifest and reset the editor.
        // Full implementation requires a get() call via the list port.
    }
}
