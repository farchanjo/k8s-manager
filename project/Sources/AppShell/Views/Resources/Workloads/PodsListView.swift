// Views/Resources/Workloads/PodsListView.swift — app_shell bounded context
// DDD role: View — Pods resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - PodsListView

/// Kubernetes Pod list view with per-row: Name / Namespace / Status / Ready /
/// Restarts / CPU / Memory / Node / Age columns.
///
/// CPU and Memory columns show "—" until Prometheus integration lands.
public struct PodsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = PodsListViewModel()

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "Pods",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            namespace: Binding(
                get: { viewModel.namespace },
                set: { viewModel.namespace = $0 }
            ),
            searchText: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            podTable
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

    // MARK: Private

    @ViewBuilder
    private var podTable: some View {
        switch viewModel.loadState {
        case .idle, .loading where viewModel.rows.isEmpty:
            loadingPlaceholder
        case .failure(let error):
            errorView(error)
        default:
            podTableContent
        }
    }

    private var podTableContent: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Status") { row in
                StatusBadge(status: row.phase.workloadStatus)
            }
            TableColumn("Ready") { row in
                Text("\(row.readyContainers)/\(row.totalContainers)")
                    .monospacedDigit()
            }
            TableColumn("Restarts") { row in
                Text("\(row.restartCount)")
                    .monospacedDigit()
            }
            TableColumn("CPU") { row in
                Text(row.cpuUsage ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(row.cpuUsage == nil ? .secondary : .primary)
            }
            TableColumn("Memory") { row in
                Text(row.memUsage ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(row.memUsage == nil ? .secondary : .primary)
            }
            TableColumn("Node", value: \.nodeName)
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Edit YAML") {}
            Button("Logs") {}
            Button("Shell") {}
            Button("Port Forward") {
                viewModel.portForwardRequested(ids: ids)
            }
            Button("Describe") {}
            Divider()
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete(ids: ids)
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading Pods…")
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
            Button("Retry") {
                Task { await viewModel.reload(clusterId: clusterId) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
