// Views/TerminalSessionView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0017 (terminal_session)

import SwiftUI
import TerminalSession

// MARK: - TerminalSessionView

/// Root view for the terminal session vertical slice.
///
/// Presents a sidebar list of sessions on the left and an interactive output
/// pane on the right. Three-state rendering follows ADR-0031: idle and loading
/// share a single progress indicator; success shows the split pane; failure
/// shows an inline error with a retry affordance.
@MainActor
public struct TerminalSessionView: View {

    @State private var viewModel: TerminalSessionViewModel
    @State private var inputText: String = ""

    public init(viewModel: TerminalSessionViewModel = TerminalSessionViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Terminal")
                .toolbar { toolbarContent }
                .task { await viewModel.loadSessions() }
        }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.sessions {
        case .idle, .loading:
            loadingView
        case .failure(let error):
            errorView(error)
        case .success(let sessions):
            sessionSplitView(sessions)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading sessions...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.body)
            Button("Retry") {
                Task { await viewModel.loadSessions() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionSplitView(_ sessions: [TerminalSession]) -> some View {
        HSplitView {
            sessionList(sessions)
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            outputPane
        }
    }

    // MARK: Session list

    private func sessionList(_ sessions: [TerminalSession]) -> some View {
        Group {
            if sessions.isEmpty {
                emptySessionList
            } else {
                List(sessions, id: \.id, selection: $viewModel.activeSessionId) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private var emptySessionList: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No sessions")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionRow(_ session: TerminalSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sessionTitle(session))
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                statusBadge(session.status)
                Text(session.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func sessionTitle(_ session: TerminalSession) -> String {
        switch session.targetRef {
        case .pod(let t): return "\(t.podName)/\(t.containerName ?? "default")"
        case .node(let t): return t.nodeName
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: SessionStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .open:    return .green
        case .opening: return .blue
        case .closing: return .orange
        case .closed:  return .gray
        case .error:   return .red
        }
    }

    // MARK: Output pane

    private var outputPane: some View {
        VStack(spacing: 0) {
            outputScrollView
            Divider()
            inputBar
        }
    }

    private var outputScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(viewModel.outputBuffer.isEmpty ? " " : viewModel.outputBuffer)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .id("output-bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: viewModel.outputBuffer) { _, _ in
                withAnimation { proxy.scrollTo("output-bottom", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Enter command…", text: $inputText)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .onSubmit { submitInput() }
            Button("Send") { submitInput() }
                .buttonStyle(.bordered)
                .disabled(inputText.isEmpty || viewModel.activeSessionId == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                // no-op: session creation requires target selection (future work)
            } label: {
                Label("New session", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .destructiveAction) {
            Button {
                Task {
                    if let id = viewModel.activeSessionId {
                        await viewModel.closeSession(id)
                    }
                }
            } label: {
                Label("Close session", systemImage: "xmark.circle")
            }
            .disabled(viewModel.activeSessionId == nil)
        }
    }

    // MARK: Helpers

    private func submitInput() {
        guard !inputText.isEmpty else { return }
        viewModel.sendInput(inputText + "\n")
        inputText = ""
    }
}
