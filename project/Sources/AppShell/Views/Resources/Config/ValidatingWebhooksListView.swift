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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.reload(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Button("Edit YAML") {}
                Button("Describe") {}
                Divider()
                Button("Delete…", role: .destructive) { viewModel.requestDelete(row) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await viewModel.reload(clusterId: clusterId) } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}
