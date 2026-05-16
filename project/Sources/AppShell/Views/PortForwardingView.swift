// Views/PortForwardingView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0014 (port-forward lifecycle)

import SwiftUI
import PortForwarding

// MARK: - PortForwardingView

/// Root view for the port-forwarding vertical slice.
///
/// Presents active ``PortForwardSession`` values with target name, port mapping,
/// and status badge. A toolbar button exposes a "New port forward" intent (modal
/// placeholder — wiring deferred until the session creation form is built).
/// Three-state rendering follows ADR-0034: idle/loading share a progress
/// indicator; success shows the session list; failure shows an inline error
/// with a Retry affordance.
@MainActor
public struct PortForwardingView: View {

    @State private var viewModel: PortForwardingViewModel
    @State private var showNewSessionSheet = false

    public init(viewModel: PortForwardingViewModel = PortForwardingViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Port Forwarding")
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
        case .success(let list):
            sessionList(list)
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

    @ViewBuilder
    private func sessionList(_ list: [PortForwardSession]) -> some View {
        if list.isEmpty {
            emptyStateView
        } else {
            List(list, id: \.id) { session in
                sessionRow(session)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No active port forwards")
                .font(.headline)
            Text("Tap \"New port forward\" to start a tunnel.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionRow(_ session: PortForwardSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(targetName(session.target))
                    .font(.headline)
                Text(portMappingLabel(session.portMappings))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(for: session.status)
            stopButton(for: session)
        }
        .padding(.vertical, 4)
    }

    private func stopButton(for session: PortForwardSession) -> some View {
        Button("Stop") {
            Task { await viewModel.stopSession(session.id) }
        }
        .buttonStyle(.bordered)
        .disabled(session.status == .closing || session.status == .closed)
    }

    @ViewBuilder
    private func statusBadge(for status: SessionStatus) -> some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(badgeColor(for: status))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showNewSessionSheet = true
            } label: {
                Label("New port forward", systemImage: "plus")
            }
            .sheet(isPresented: $showNewSessionSheet) {
                newSessionPlaceholder
            }
        }
    }

    private var newSessionPlaceholder: some View {
        VStack(spacing: 16) {
            Text("New Port Forward")
                .font(.title2.bold())
            Text("Session creation form — not yet implemented.")
                .foregroundStyle(.secondary)
            Button("Close") { showNewSessionSheet = false }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 200)
    }

    // MARK: Helpers

    private func targetName(_ target: ForwardTarget) -> String {
        switch target {
        case .pod(let t): "\(t.namespace)/\(t.podName)"
        case .service(let t): "\(t.namespace)/\(t.serviceName)"
        }
    }

    private func portMappingLabel(_ mappings: [PortMapping]) -> String {
        mappings
            .map { "\($0.localPort) → \($0.remotePort)" }
            .joined(separator: ", ")
    }

    private func badgeColor(for status: SessionStatus) -> Color {
        switch status {
        case .running: .green
        case .opening: .blue
        case .closing: .orange
        case .closed: .gray
        case .error: .red
        }
    }
}
