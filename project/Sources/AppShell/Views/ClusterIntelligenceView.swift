// Views/ClusterIntelligenceView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI)

import SwiftUI
import ClusterIntelligence

// MARK: - ClusterIntelligenceView

/// Diagnostics panel for the cluster intelligence bounded context.
///
/// Displays the registered MCP tool catalogue (tool count header, tool list
/// with name, description, and allowed Kubernetes verbs) and a recent
/// invocations log with outcome badges. Three-state rendering per section
/// follows ADR-0031: idle/loading share a progress indicator; success shows
/// the data; failure shows an inline error with a retry affordance.
@MainActor
public struct ClusterIntelligenceView: View {

    @State private var viewModel: ClusterIntelligenceViewModel

    public init(viewModel: ClusterIntelligenceViewModel = ClusterIntelligenceViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Intelligence")
                .task {
                    async let r: () = viewModel.loadRegistry()
                    async let i: () = viewModel.loadRecentInvocations()
                    _ = await (r, i)
                }
        }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        List {
            registrySection
            invocationsSection
        }
    }

    // MARK: Registry section

    @ViewBuilder
    private var registrySection: some View {
        Section {
            switch viewModel.registry {
            case .idle, .loading:
                loadingRow(label: "Loading tool registry…")
            case .failure(let error):
                errorRow(error, retry: { Task { await viewModel.loadRegistry() } })
            case .success(let snapshot):
                registryContent(snapshot)
            }
        } header: {
            registryHeader
        }
    }

    @ViewBuilder
    private var registryHeader: some View {
        if let snapshot = viewModel.registry.value {
            Label(
                "Registered Tools (\(snapshot.toolDescriptors.count))",
                systemImage: "brain"
            )
        } else {
            Label("Registered Tools", systemImage: "brain")
        }
    }

    @ViewBuilder
    private func registryContent(_ snapshot: MCPRegistrySnapshotReadModel) -> some View {
        if snapshot.toolDescriptors.isEmpty {
            Text("No tools registered")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(snapshot.toolDescriptors, id: \.name) { descriptor in
                toolRow(descriptor)
            }
        }
    }

    private func toolRow(_ descriptor: (name: String, description: String)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(descriptor.name)
                .font(.headline)
                .monospaced()
            Text(descriptor.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    // MARK: Invocations section

    @ViewBuilder
    private var invocationsSection: some View {
        Section("Recent Invocations") {
            switch viewModel.recentInvocations {
            case .idle, .loading:
                loadingRow(label: "Loading invocations…")
            case .failure(let error):
                errorRow(error, retry: { Task { await viewModel.loadRecentInvocations() } })
            case .success(let log):
                invocationsContent(log)
            }
        }
    }

    @ViewBuilder
    private func invocationsContent(_ log: MCPInvocationLogReadModel) -> some View {
        if log.entries.isEmpty {
            Text("No invocations recorded")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(log.entries, id: \.id) { invocation in
                invocationRow(invocation)
            }
        }
    }

    private func invocationRow(_ invocation: MCPInvocation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invocation.toolName)
                    .font(.headline)
                    .monospaced()
                Text(invocation.requestedAtRFC3339)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            outcomeBadge(for: invocation.outcome)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func outcomeBadge(for outcome: MCPOutcome) -> some View {
        let (label, color) = outcomeLabelAndColor(for: outcome)
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func outcomeLabelAndColor(for outcome: MCPOutcome) -> (String, Color) {
        switch outcome {
        case .succeeded:        return ("succeeded", .green)
        case .deniedByPolicy:   return ("denied", .orange)
        case .failed:           return ("failed", .red)
        case .cancelled:        return ("cancelled", .gray)
        }
    }

    // MARK: Shared row helpers

    private func loadingRow(label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorRow(_ error: Error, retry: @escaping @Sendable () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.localizedDescription)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
            }
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
