// Views/Resources/Config/ResourceQuotasListView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - ResourceQuotasListView

/// Table view listing Kubernetes ResourceQuotas for a given cluster and namespace.
@MainActor
public struct ResourceQuotasListView: View {

    let clusterId: ClusterId
    @State private var viewModel = ResourceQuotasListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                WorkloadListSkeleton()
            case .failure(let error):
                errorView(error)
            case .success:
                tableView
            }
        }
        .navigationTitle("ResourceQuotas")
        .toolbar { toolbarContent }
        .task { await viewModel.start(clusterId: clusterId, namespace: nil) }
        .alert("Delete ResourceQuota?", isPresented: $viewModel.showDeleteConfirm) {
            Button("Delete", role: .destructive) { viewModel.pendingDeleteRow = nil }
            Button("Cancel", role: .cancel) { viewModel.pendingDeleteRow = nil }
        } message: { Text("This action cannot be undone.") }
    }

    private func errorView(_ error: Error) -> some View {
        ErrorStateView(
            title: "Failed to load ResourceQuotas",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }

    private var tableView: some View {
        Table(viewModel.rows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Hard Limits", value: \.hardLimits)
            TableColumn("Used", value: \.used)
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let row = viewModel.rows.first(where: { ids.contains($0.id) }) {
                let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                    kind: "ResourceQuota", name: row.name, namespace: row.namespace, family: .config
                ))
                ForEach(actions) { action in
                    if action.id == "delete" {
                        Divider()
                        Button("Delete\u{2026}", role: .destructive) { viewModel.requestDelete(row) }
                    } else {
                        Button(action.label) {}
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            ExportMenu(
                kind: "ResourceQuota",
                rows: viewModel.rows.map { row in
                    ResourceListRow(values: [
                        row.name, row.namespace, row.hardLimits, row.used, row.age,
                    ])
                },
                isHidden: viewModel.rows.isEmpty
            )
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await viewModel.reload(clusterId: clusterId) } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}
