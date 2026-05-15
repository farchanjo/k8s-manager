// Views/ClusterListView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI)

import SwiftUI
import ClusterConnectivity

// MARK: - ClusterListView

/// Root view for the cluster connectivity vertical slice.
///
/// Presents kubeconfig contexts and allows per-context health probing.
/// Three-state rendering follows ADR-0031: idle and loading share a single
/// progress indicator; success shows the context list; failure shows an
/// inline error with a retry affordance.
@MainActor
public struct ClusterListView: View {

    @State private var viewModel: ClusterListViewModel

    public init(viewModel: ClusterListViewModel = ClusterListViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Clusters")
                .task { await viewModel.loadKubeconfig() }
        }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.contexts {
        case .idle, .loading:
            loadingView
        case .failure(let error):
            errorView(error)
        case .success(let contexts):
            contextList(contexts)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading kubeconfig...")
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
                Task { await viewModel.loadKubeconfig() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contextList(_ contexts: [KubeconfigContext]) -> some View {
        List(contexts, id: \.name) { context in
            contextRow(context)
        }
    }

    private func contextRow(_ context: KubeconfigContext) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.name).font(.headline)
                Text("Cluster: \(context.cluster)").font(.caption).foregroundStyle(.secondary)
                Text("Namespace: \(context.namespace)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            healthBadge(for: context)
            Button("Probe") {
                Task { await viewModel.probeHealth(for: context) }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func healthBadge(for context: KubeconfigContext) -> some View {
        switch viewModel.healthByContext[context.name] {
        case .none, .some(.idle):
            EmptyView()
        case .some(.loading):
            ProgressView().controlSize(.small)
        case .some(.success(let status)):
            Text(status.state.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(badgeColor(for: status.state))
                .foregroundStyle(.white)
                .clipShape(Capsule())
        case .some(.failure):
            Image(systemName: "xmark.circle")
                .foregroundStyle(.red)
        }
    }

    private func badgeColor(for state: HealthState) -> Color {
        switch state {
        case .reachable: return .green
        case .degraded: return .orange
        case .unreachable, .unauthorized, .forbidden: return .red
        case .unknown: return .gray
        }
    }
}
