// Views/Resources/Workloads/ReplicaSetsListView.swift — app_shell bounded context
// DDD role: View — ReplicaSets resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - ReplicaSetsListView

/// Kubernetes ReplicaSet list view with per-row:
/// Name / Namespace / Desired / Current / Ready / Age columns.
public struct ReplicaSetsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = ReplicaSetsListViewModel()

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "ReplicaSets",
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
        .task(id: clusterId) {
            await viewModel.start(clusterId: clusterId, namespace: namespace)
        }
    }

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "No replicasets match \"\(viewModel.searchText)\"."
        }
        if let ns = viewModel.namespace {
            return "Namespace \"\(ns)\" has no replicasets."
        }
        return "This cluster has no replicasets."
    }

    private var emptyStateSystemImage: String { "rectangle.on.rectangle" }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.loadState {
        case .idle where viewModel.rows.isEmpty,
             .loading where viewModel.rows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            ErrorStateView(
                title: "Failed to load ReplicaSets",
                error: error,
                retryable: true,
                onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
            )
        case .success where viewModel.filteredRows.isEmpty:
            EmptyStateView(
                title: "No ReplicaSets",
                message: emptyStateMessage,
                systemImage: emptyStateSystemImage
            )
        default:
            replicaSetsTable
        }
    }

    private var replicaSetsTable: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Desired") { row in Text("\(row.desired)").monospacedDigit() }
            TableColumn("Current") { row in Text("\(row.current)").monospacedDigit() }
            TableColumn("Ready") { row in Text("\(row.ready)").monospacedDigit() }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Edit YAML") {}
            Button("Describe") {}
            Divider()
            Button("Delete", role: .destructive) { viewModel.confirmDelete(ids: ids) }
        }
    }

}
