// Views/Resources/RBAC/ClusterRolesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, RBAC category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - ClusterRolesListViewModel

/// View model for the Kubernetes ClusterRoles list view.
///
/// Cluster-scoped. Loads `rbac.authorization.k8s.io/v1 ClusterRole`.
@Observable
@MainActor
public final class ClusterRolesListViewModel {

    // MARK: State

    /// Lifecycle state of the cluster roles list.
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

    private let logger = Logger(label: "k8smgr.app_shell.cluster_roles_list")

    private static let gvk = GroupVersionKind(
        group: "rbac.authorization.k8s.io", version: "v1", kind: "ClusterRole"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads cluster roles for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches cluster roles.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("clusterroles reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: Self.gvk, namespace: nil, clusterId: clusterId)
            logger.info("clusterroles loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("clusterroles load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - ClusterRolesListView

/// Displays cluster-scoped Kubernetes ClusterRoles: Name / Age.
@MainActor
public struct ClusterRolesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = ClusterRolesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Cluster Roles",
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
                ClusterRoleRow(item: item)
                    .contextMenu {
                        let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                            kind: "ClusterRole", name: item.name, family: .accessControl
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
            title: "Failed to load ClusterRoles",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}

// MARK: - ClusterRoleRow

private struct ClusterRoleRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(item.name).font(.body.monospaced())
                if item.name.hasPrefix("system:") {
                    Text("system")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
