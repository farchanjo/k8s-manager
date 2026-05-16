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
        .task(id: clusterId) {
            await viewModel.start(clusterId: clusterId, namespace: namespace)
        }
    }

    // MARK: Private

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "No pods match \"\(viewModel.searchText)\"."
        }
        if let ns = viewModel.namespace {
            return "Namespace \"\(ns)\" has no pods."
        }
        return "This cluster has no pods."
    }

    private var emptyStateSystemImage: String { "shippingbox" }

    @ViewBuilder
    private var podTable: some View {
        switch viewModel.loadState {
        case .idle where viewModel.rows.isEmpty,
             .loading where viewModel.rows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            ErrorStateView(
                title: "Failed to load Pods",
                error: error,
                retryable: true,
                onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
            )
        case .success where viewModel.filteredRows.isEmpty:
            EmptyStateView(
                title: "No Pods",
                message: emptyStateMessage,
                systemImage: emptyStateSystemImage
            )
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

}
