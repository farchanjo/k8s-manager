// Views/Resources/Config/ValidatingWebhooksListView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (resource navigation taxonomy)
// Note: cluster-scoped — no namespace picker.

import SwiftUI
import SharedKernel

// MARK: - ValidatingWebhooksListView

/// Table view listing Kubernetes ValidatingWebhookConfigurations (cluster-scoped).
@MainActor
public struct ValidatingWebhooksListView: View {

    let clusterId: ClusterId
    @State private var viewModel = ValidatingWebhooksListViewModel()

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
        .navigationTitle("ValidatingWebhookConfigurations")
        .toolbar { toolbarContent }
        .task { await viewModel.start(clusterId: clusterId) }
        .alert("Delete ValidatingWebhookConfiguration?", isPresented: $viewModel.showDeleteConfirm) {
            Button("Delete", role: .destructive) { viewModel.pendingDeleteRow = nil }
            Button("Cancel", role: .cancel) { viewModel.pendingDeleteRow = nil }
        } message: { Text("This action cannot be undone.") }
    }

    private func errorView(_ error: Error) -> some View {
        ErrorStateView(
            title: "Failed to load ValidatingWebhookConfigurations",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }

    private var tableView: some View {
        Table(viewModel.rows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Webhooks") { row in
                Text("\(row.webhooksCount)").monospacedDigit()
            }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let row = viewModel.rows.first(where: { ids.contains($0.id) }) {
                let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                    kind: "ValidatingWebhookConfiguration", name: row.name, family: .config
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
                kind: "ValidatingWebhookConfiguration",
                rows: viewModel.rows.map { row in
                    ResourceListRow(values: [
                        row.name, "\(row.webhooksCount)", row.age,
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
