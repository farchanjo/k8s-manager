// Views/Resources/Network/EndpointSlicesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Network category)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - EndpointSlicesListViewModel

/// View model for the Kubernetes EndpointSlices list view.
///
/// Loads `discovery.k8s.io/v1 EndpointSlice` via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class EndpointSlicesListViewModel {

    // MARK: State

    /// Lifecycle state of the endpoint slices list.
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

    private let logger = Logger(label: "k8smgr.app_shell.endpoint_slices_list")

    private static let gvk = GroupVersionKind(
        group: "discovery.k8s.io", version: "v1", kind: "EndpointSlice"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads endpoint slices for the given cluster and namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    /// Re-fetches endpoint slices with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("endpointslices reload cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        do {
            let items = try await listPort.list(
                gvk: Self.gvk, namespace: namespace, clusterId: clusterId
            )
            logger.info("endpointslices loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("endpointslices load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - EndpointSlicesListView

/// Displays Kubernetes EndpointSlices: Name / Namespace / Status / Age.
@MainActor
public struct EndpointSlicesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = EndpointSlicesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Endpoint Slices",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            namespace: $viewModel.namespace,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            content
        }
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
                            kind: "EndpointSlice", name: item.name,
                            namespace: item.namespace, family: .network
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
            title: "Failed to load EndpointSlices",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}
