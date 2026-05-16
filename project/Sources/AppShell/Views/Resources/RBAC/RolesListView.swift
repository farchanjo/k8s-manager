// Views/Resources/RBAC/RolesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, RBAC category)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - RolesListViewModel

/// View model for the Kubernetes Roles list view.
///
/// Loads `rbac.authorization.k8s.io/v1 Role` via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class RolesListViewModel {

    // MARK: State

    /// Lifecycle state of the roles list.
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

    private let logger = Logger(label: "k8smgr.app_shell.roles_list")

    private static let gvk = GroupVersionKind(
        group: "rbac.authorization.k8s.io", version: "v1", kind: "Role"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads roles for the given cluster and namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    /// Re-fetches roles with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("roles reload cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        do {
            let items = try await listPort.list(
                gvk: Self.gvk, namespace: namespace, clusterId: clusterId
            )
            logger.info("roles loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("roles load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - RolesListView

/// Displays Kubernetes Roles: Name / Namespace / Age.
@MainActor
public struct RolesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = RolesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Roles",
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
            }
            .listStyle(.inset)
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
