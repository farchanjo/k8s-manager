// Views/Resources/Workloads/ReplicationControllersListView.swift — app_shell bounded context
// DDD role: View — ReplicationControllers resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - ReplicationControllersListView

/// Kubernetes ReplicationController list view with per-row:
/// Name / Namespace / Desired / Current / Ready / Age columns.
public struct ReplicationControllersListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = ReplicationControllersListViewModel()

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "ReplicationControllers",
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
            return "No replicationcontrollers match \"\(viewModel.searchText)\"."
        }
        if let ns = viewModel.namespace {
            return "Namespace \"\(ns)\" has no replicationcontrollers."
        }
        return "This cluster has no replicationcontrollers."
    }

    private var emptyStateSystemImage: String { "arrow.triangle.2.circlepath" }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.loadState {
        case .idle where viewModel.rows.isEmpty,
             .loading where viewModel.rows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            ErrorStateView(
                title: "Failed to load ReplicationControllers",
                error: error,
                retryable: true,
                onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
            )
        case .success where viewModel.filteredRows.isEmpty:
            EmptyStateView(
                title: "No ReplicationControllers",
                message: emptyStateMessage,
                systemImage: emptyStateSystemImage
            )
        default:
            rcTable
        }
    }

    private var rcTable: some View {
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
