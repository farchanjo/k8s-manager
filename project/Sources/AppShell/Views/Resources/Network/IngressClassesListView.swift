// Views/Resources/Network/IngressClassesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Network category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - IngressClassesListViewModel

/// View model for the Kubernetes IngressClasses list view.
///
/// Cluster-scoped; no namespace filter. Loads
/// `networking.k8s.io/v1 IngressClass` via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class IngressClassesListViewModel {

    // MARK: State

    /// Lifecycle state of the ingress classes list.
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

    private let logger = Logger(label: "k8smgr.app_shell.ingress_classes_list")

    private static let gvk = GroupVersionKind(
        group: "networking.k8s.io", version: "v1", kind: "IngressClass"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads ingress classes for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches ingress classes.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("ingressclasses reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: Self.gvk, namespace: nil, clusterId: clusterId)
            logger.info("ingressclasses loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("ingressclasses load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - IngressClassesListView

/// Displays cluster-scoped Kubernetes IngressClasses: Name / Controller / Age.
@MainActor
public struct IngressClassesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = IngressClassesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Ingress Classes",
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
                SimpleClusterScopedRow(
                    item: item,
                    secondary: item.annotations["ingressclass.kubernetes.io/is-default-class"] == "true"
                        ? "default" : nil
                )
            }
            .listStyle(.inset)
        }
    }

    private func errorView(_ error: Error) -> some View {
        ErrorStateView(
            title: "Failed to load IngressClasses",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}
