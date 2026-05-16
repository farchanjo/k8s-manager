// Views/Resources/Storage/PVCsListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Storage category)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - PVCsListViewModel

/// View model for the Kubernetes PersistentVolumeClaims list view.
///
/// Loads core/v1 PersistentVolumeClaim via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class PVCsListViewModel {

    // MARK: State

    /// Lifecycle state of the PVCs list.
    public var loadState: AsyncResource<[ResourceListItem]> = .idle

    /// Active namespace filter. `nil` means all namespaces.
    public var namespace: String?

    /// Free-text search filter applied client-side.
    public var searchText: String = ""

    // MARK: Computed

    /// Rows after applying the search filter.
    public var filteredRows: [ResourceListItem] {
        guard let items = loadState.value, !searchText.isEmpty else {
            return loadState.value ?? []
        }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.namespace ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    private let logger = Logger(label: "k8smgr.app_shell.pvcs_list")

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads PVCs for the given cluster and namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    /// Re-fetches PVCs with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("pvcs reload cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        let gvk = GroupVersionKind.core("PersistentVolumeClaim")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            logger.info("pvcs loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("pvcs load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - PVCsListView

/// Displays Kubernetes PersistentVolumeClaims: Name / Namespace / Status / Age.
@MainActor
public struct PVCsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = PVCsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Persistent Volume Claims",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            namespace: $viewModel.namespace,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            content
        }
        .modifier(ExportMenuContainer(
            kind: "PersistentVolumeClaim",
            rows: viewModel.filteredRows.map { item in
                ResourceListRow(values: [
                    item.name, item.namespace ?? "", item.status,
                    ageLabel(item.ageSeconds),
                ])
            },
            isHidden: viewModel.filteredRows.isEmpty
        ))
        .task { await viewModel.start(clusterId: clusterId, namespace: nil) }
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
                SimpleResourceRow(item: item)
                    .contextMenu {
                        let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                            kind: "PersistentVolumeClaim", name: item.name,
                            namespace: item.namespace, family: .storage
                        ))
                        ForEach(actions) { action in
                            if action.id == "delete" {
                                Divider()
                                Button("Delete\u{2026}", role: .destructive) {}
                            } else {
                                Button(action.label) {}
                            }
                        }
                    }
            }
            .listStyle(.inset)
        }
    }

    private func errorView(_ error: Error) -> some View {
        ErrorStateView(
            title: "Failed to load PersistentVolumeClaims",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}
