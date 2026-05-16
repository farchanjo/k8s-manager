// Views/AssistantChatView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI)

import SwiftUI
import AssistantChat

// MARK: - AssistantChatView

/// Root view for the assistant chat vertical slice.
///
/// Presents a two-column layout: a session sidebar on the left and the
/// active conversation on the right. Three-state rendering follows ADR-0031:
/// idle and loading share a progress indicator; success shows content;
/// failure shows an inline error with a retry affordance.
@MainActor
public struct AssistantChatView: View {

    @State private var viewModel: AssistantChatViewModel

    public init(viewModel: AssistantChatViewModel = AssistantChatViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            sessionSidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            conversationPanel
        }
        .task { await viewModel.loadSessions() }
    }

    // MARK: Session sidebar

    @ViewBuilder
    private var sessionSidebar: some View {
        switch viewModel.sessions {
        case .idle, .loading:
            sidebarLoadingView
        case .failure(let error):
            sidebarErrorView(error)
        case .success(let sessions):
            sessionList(sessions)
        }
    }

    private var sidebarLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading sessions...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebarErrorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.caption)
            Button("Retry") {
                Task { await viewModel.loadSessions() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionList(_ sessions: [ChatSession]) -> some View {
        List(sessions, id: \.id, selection: Binding(
            get: { viewModel.currentSession },
            set: { session in
                guard let session else { return }
                Task { await viewModel.selectSession(session) }
            }
        )) { session in
            sessionRow(session)
        }
        .listStyle(.sidebar)
        .navigationTitle("Sessions")
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(.headline)
                .lineLimit(1)
            Text("\(session.turnCount) turns")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Conversation panel

    @ViewBuilder
    private var conversationPanel: some View {
        if viewModel.currentSession == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                messageArea
                Divider()
                inputBar
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Select a session",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Pick a conversation from the sidebar")
        )
    }

    @ViewBuilder
    private var messageArea: some View {
        switch viewModel.messages {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            messageErrorView(error)
        case .success(let msgs):
            messageList(msgs)
        }
    }

    private func messageErrorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageList(_ messages: [ChatMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages, id: \.id) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer() }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground(for: message.role))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if message.streaming {
                    Text("typing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if message.role != .user { Spacer() }
        }
    }

    private func bubbleBackground(for role: MessageRole) -> Color {
        role == .user ? .accentColor : Color(nsColor: .controlBackgroundColor)
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $viewModel.draftInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit { sendDraft() }
            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendDraft() {
        let text = viewModel.draftInput
        Task { await viewModel.sendMessage(text) }
    }
}
