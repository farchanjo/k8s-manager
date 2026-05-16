// Views/Resources/Cluster/NamespacesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Cluster category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - NamespacesListViewModel

/// View model for the Kubernetes Namespaces list view.
///
/// Cluster-scoped. Loads core/v1 Namespace via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class NamespacesListViewModel {

    // MARK: State

    /// Lifecycle state of the namespaces list.
    public var loadState: AsyncResource<[ResourceListItem]> = .idle

    /// Free-text search filter applied client-side.
    public var searchText: String = ""

    // MARK: Computed

    /// Rows after applying the search filter.
    public var filteredRows: [ResourceListItem] {
        guard let items = loadState.value, !searchText.isEmpty else {
            return loadState.value ?? []
        }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    private let logger = Logger(label: "k8smgr.app_shell.namespaces_list")

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads namespaces for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches namespaces.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("namespaces reload cluster=\(clusterId.rawValue)")
        let gvk = GroupVersionKind.core("Namespace")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            logger.info("namespaces loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("namespaces load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - NamespacesListView

/// Displays cluster-scoped Kubernetes Namespaces: Name / Status / Age.
@MainActor
public struct NamespacesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = NamespacesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Namespaces",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            content
        }
        .task { await viewModel.start(clusterId: clusterId) }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading where viewModel.filteredRows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            errorView(error)
        default:
            List(viewModel.filteredRows, id: \.uid) { item in
                NamespaceRow(item: item)
            }
            .listStyle(.inset)
        }
    }

    private func errorView(_ error: Error) -> some View {
        ErrorStateView(
            title: "Failed to load Namespaces",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}

// MARK: - NamespaceRow

private struct NamespaceRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            Text(item.name).font(.body.monospaced())
            Spacer()
            StatusChip(
                variant: StatusChipSemantic.chipVariant(forRawStatus: item.status),
                label: item.status
            )
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
