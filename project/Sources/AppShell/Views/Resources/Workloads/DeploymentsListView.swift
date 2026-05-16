// Views/Resources/Workloads/DeploymentsListView.swift — app_shell bounded context
// DDD role: View — Deployments resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - DeploymentsListView

/// Kubernetes Deployment list view with per-row:
/// Name / Namespace / Pods / Replicas / Available / Age columns.
public struct DeploymentsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = DeploymentsListViewModel()

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "Deployments",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            searchText: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            tableContent
        }
        .task { await viewModel.start(clusterId: clusterId, namespace: namespace) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NamespaceFilterPicker(selection: Binding(
                    get: { viewModel.namespace },
                    set: { ns in
                        viewModel.namespace = ns
                        Task { await viewModel.reload(clusterId: clusterId) }
                    }
                ))
            }
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.loadState {
        case .idle, .loading where viewModel.rows.isEmpty:
            loadingView
        case .failure(let error):
            errorView(error)
        default:
            deploymentsTable
        }
    }

    private var deploymentsTable: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Pods") { row in
                Text(row.podsReady).monospacedDigit()
            }
            TableColumn("Replicas") { row in
                Text("\(row.replicas)").monospacedDigit()
            }
            TableColumn("Available") { row in
                Text("\(row.available)").monospacedDigit()
            }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Edit YAML") {}
            Button("Describe") {}
            Divider()
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete(ids: ids)
            }
        }
    }

    private var loadingView: some View {
        ProgressView("Loading Deployments…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.orange)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.reload(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
