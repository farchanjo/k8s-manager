// Views/Resources/Workloads/JobsListView.swift — app_shell bounded context
// DDD role: View — Jobs resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - JobsListView

/// Kubernetes Job list view with per-row:
/// Name / Namespace / Completions / Duration / Age columns.
public struct JobsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = JobsListViewModel()

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "Jobs",
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
            return "No jobs match \"\(viewModel.searchText)\"."
        }
        if let ns = viewModel.namespace {
            return "Namespace \"\(ns)\" has no jobs."
        }
        return "This cluster has no jobs."
    }

    private var emptyStateSystemImage: String { "checkmark.circle" }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.loadState {
        case .idle where viewModel.rows.isEmpty,
             .loading where viewModel.rows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            ErrorStateView(
                title: "Failed to load Jobs",
                error: error,
                retryable: true,
                onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
            )
        case .success where viewModel.filteredRows.isEmpty:
            EmptyStateView(
                title: "No Jobs",
                message: emptyStateMessage,
                systemImage: emptyStateSystemImage
            )
        default:
            jobsTable
        }
    }

    private var jobsTable: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Completions") { row in Text(row.completions).monospacedDigit() }
            TableColumn("Duration") { row in
                Text(row.duration ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(row.duration == nil ? .secondary : .primary)
            }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                kind: "Job", name: ids.first ?? "", family: .workloads
            ))
            ForEach(actions) { action in
                if action.id == "delete" {
                    Divider()
                    Button("Delete\u{2026}", role: .destructive) { viewModel.confirmDelete(ids: ids) }
                } else {
                    Button(action.label) {}
                }
            }
        }
    }

}
