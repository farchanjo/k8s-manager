// Views/Resources/Workloads/DaemonSetsListView.swift — app_shell bounded context
// DDD role: View — DaemonSets resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - DaemonSetsListView

/// Kubernetes DaemonSet list view with per-row:
/// Name / Namespace / Desired / Current / Ready / Up-to-date / Available / Age.
public struct DaemonSetsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = DaemonSetsListViewModel()

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "DaemonSets",
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
            ProgressView("Loading DaemonSets…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error)
        default:
            daemonSetsTable
        }
    }

    private var daemonSetsTable: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Desired") { row in Text("\(row.desired)").monospacedDigit() }
            TableColumn("Current") { row in Text("\(row.current)").monospacedDigit() }
            TableColumn("Ready") { row in Text("\(row.ready)").monospacedDigit() }
            TableColumn("Up-to-date") { row in Text("\(row.upToDate)").monospacedDigit() }
            TableColumn("Available") { row in Text("\(row.available)").monospacedDigit() }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Edit YAML") {}
            Button("Describe") {}
            Divider()
            Button("Delete", role: .destructive) { viewModel.confirmDelete(ids: ids) }
        }
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
}
