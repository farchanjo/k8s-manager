// Views/Resources/Workloads/CronJobsListView.swift — app_shell bounded context
// DDD role: View — CronJobs resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - CronJobsListView

/// Kubernetes CronJob list view with per-row:
/// Name / Namespace / Schedule / Suspend / Active / Last Schedule / Age columns.
public struct CronJobsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = CronJobsListViewModel()

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "CronJobs",
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
            return "No cronjobs match \"\(viewModel.searchText)\"."
        }
        if let ns = viewModel.namespace {
            return "Namespace \"\(ns)\" has no cronjobs."
        }
        return "This cluster has no cronjobs."
    }

    private var emptyStateSystemImage: String { "clock.arrow.circlepath" }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.loadState {
        case .idle where viewModel.rows.isEmpty,
             .loading where viewModel.rows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            ErrorStateView(
                title: "Failed to load CronJobs",
                error: error,
                retryable: true,
                onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
            )
        case .success where viewModel.filteredRows.isEmpty:
            EmptyStateView(
                title: "No CronJobs",
                message: emptyStateMessage,
                systemImage: emptyStateSystemImage
            )
        default:
            cronJobsTable
        }
    }

    private var cronJobsTable: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Schedule", value: \.schedule)
            TableColumn("Suspend") { row in
                Text(row.isSuspended ? "True" : "False")
                    .foregroundStyle(row.isSuspended ? .secondary : .primary)
            }
            TableColumn("Active") { row in Text("\(row.activeCount)").monospacedDigit() }
            TableColumn("Last Schedule") { row in
                Text(row.lastSchedule ?? "—")
                    .foregroundStyle(row.lastSchedule == nil ? .secondary : .primary)
            }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Edit YAML") {}
            Button("Trigger Now") {}
            Button("Describe") {}
            Divider()
            Button("Delete", role: .destructive) { viewModel.confirmDelete(ids: ids) }
        }
    }

}
