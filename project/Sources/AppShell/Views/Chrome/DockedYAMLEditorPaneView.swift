// Views/Chrome/DockedYAMLEditorPane.swift — app_shell bounded context
// DDD role: View — inline docked YAML editor pane chrome
// ADR ref: ADR-0064 (inline docked YAML editor pane)

import SwiftUI
import SharedKernel

// MARK: - DockedYAMLEditorPane

/// Inline docked YAML editor pane: resize handle, breadcrumb header, and
/// the active editor surface (reuses ``YAMLEditorTab`` infrastructure).
///
/// Per ADR-0064 §Coexistence this pane and ``DockedTerminalPane`` are mutually
/// exclusive: the `SidebarCanvasView` renders at most one at a time. This view
/// is only placed in the view tree when it is the active docked pane.
///
/// The pane slides up from the bottom with a spring animation on open and
/// slides down on close.
public struct DockedYAMLEditorPane: View {

    // MARK: Input

    /// Actor owning the editor pane state. Passed in by `SidebarCanvasView`.
    let actor: DockedYAMLEditorPaneActor

    // MARK: Observed state

    @State private var snapshot: DockedYAMLEditorPaneSnapshot = .init(
        state: DockedYAMLEditorPaneState()
    )

    // MARK: Geometry state

    @State private var localHeight: Double = 300
    @State private var dragBaseHeight: Double = 300
    @State private var preFullscreenHeight: Double = 300

    // MARK: Unsaved-changes guard

    @State private var showingDiscardSheet = false

    // MARK: Body

    public var body: some View {
        Group {
            if snapshot.isOpen {
                paneContent
                    .frame(height: snapshot.state.fullscreen ? nil : localHeight)
                    .frame(maxHeight: snapshot.state.fullscreen ? .infinity : nil)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.08), value: snapshot.isOpen)
        .task {
            for await s in await actor.stateStream() {
                snapshot = s
                if !s.state.fullscreen {
                    localHeight = s.state.paneHeight
                }
            }
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showingDiscardSheet,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                Task { await actor.closeDraft() }
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            if let draft = snapshot.activeDraft {
                Text(
                    "Your edits to \(draft.ref.kind.kind)/\(draft.ref.name) " +
                    "have not been applied. Discard them?"
                )
            }
        }
    }

    // MARK: - Pane content

    private var paneContent: some View {
        VStack(spacing: 0) {
            resizeHandle
            Divider()
            paneHeader
            Divider()
            if let draft = snapshot.activeDraft {
                terminalSessionBanner
                editorBody(draft: draft)
            }
        }
        .background(.windowBackground)
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        Color.primary.opacity(0.12)
            .frame(height: 4)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture(count: 2) { resetHeight() }
            .accessibilityLabel("Drag to resize YAML editor pane")
            .accessibilityIdentifier("DockedYAMLEditorPane.ResizeHandle")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let delta = -value.translation.height
                localHeight = max(200, dragBaseHeight + delta)
            }
            .onEnded { _ in
                dragBaseHeight = localHeight
                Task { await actor.setPaneHeight(localHeight) }
            }
    }

    private func resetHeight() {
        localHeight = 300
        dragBaseHeight = 300
        Task { await actor.setPaneHeight(300) }
    }

    // MARK: - Pane header

    private var paneHeader: some View {
        HStack(spacing: 8) {
            breadcrumb
            Spacer(minLength: 0)
            diffToggleButton
            fullscreenToggleButton
            saveButton
            discardButton
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.bar)
    }

    private var breadcrumb: some View {
        Text(breadcrumbText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("DockedYAMLEditorPane.Breadcrumb")
    }

    private var breadcrumbText: String {
        guard let draft = snapshot.activeDraft else { return "" }
        let ref = draft.ref
        if let ns = ref.namespace {
            return "Editing kubernetes \(ref.kind.kind) \(ref.name) in namespace \(ns)"
        }
        return "Editing kubernetes \(ref.kind.kind) \(ref.name)"
    }

    private var diffToggleButton: some View {
        Button {
            Task { await actor.toggleDiffOverlay() }
        } label: {
            Text("Diff")
                .font(.system(size: 11))
                .foregroundStyle(
                    snapshot.activeDraft?.isDiffOverlayVisible == true ? .primary : .secondary
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle diff overlay")
        .accessibilityIdentifier("DockedYAMLEditorPane.DiffToggle")
    }

    private var fullscreenToggleButton: some View {
        Button {
            Task { await toggleFullscreen() }
        } label: {
            Image(
                systemName: snapshot.state.fullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right"
            )
            .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            snapshot.state.fullscreen ? "Collapse editor pane" : "Expand editor pane"
        )
    }

    private var saveButton: some View {
        Button("Save") {
            // Save triggers the ADR-0030 apply pipeline via the view model.
            // Full wiring to YAMLEditorViewModel is deferred to composition root.
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!(snapshot.activeDraft?.isDirty ?? false))
        .accessibilityIdentifier("DockedYAMLEditorPane.SaveButton")
    }

    private var discardButton: some View {
        Button("Discard") {
            guard let draft = snapshot.activeDraft else { return }
            if draft.isDirty {
                showingDiscardSheet = true
            } else {
                Task { await actor.closeDraft() }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("DockedYAMLEditorPane.DiscardButton")
    }

    // MARK: - Terminal running banner (ADR-0064 §Coexistence)

    @ViewBuilder
    private var terminalSessionBanner: some View {
        if snapshot.state.showTerminalRunningBanner {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                Text("Terminal sessions are running in the background. Open terminal to resume.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.yellow.opacity(0.1))
            .accessibilityIdentifier("DockedYAMLEditorPane.TerminalBanner")
        }
    }

    // MARK: - Editor body

    @ViewBuilder
    private func editorBody(draft: DockedEditorDraft) -> some View {
        if draft.isDiffOverlayVisible {
            diffView(draft: draft)
        } else {
            singlePaneEditor(draft: draft)
        }
    }

    private func singlePaneEditor(draft: DockedEditorDraft) -> some View {
        // The full editor view (YAMLEditorTab) is the precedent;
        // in the docked pane we embed a simplified read/edit surface
        // re-using the same CodeEditorPort via the environment.
        Color.black
            .overlay(
                Text(draft.draftText.isEmpty ? "Loading manifest…" : "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("DockedYAMLEditorPane.EditorSurface")
    }

    private func diffView(draft: DockedEditorDraft) -> some View {
        HSplitView {
            // Left: server-state (read-only)
            Color.black
                .overlay(
                    Text("Server state")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                )
            // Right: operator's edits
            Color.black
                .overlay(
                    Text(draft.draftText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("DockedYAMLEditorPane.DiffView")
    }

    // MARK: - Private helpers

    private func toggleFullscreen() async {
        if !snapshot.state.fullscreen {
            preFullscreenHeight = localHeight
        } else {
            localHeight = preFullscreenHeight
        }
        await actor.toggleFullscreen()
    }
}
