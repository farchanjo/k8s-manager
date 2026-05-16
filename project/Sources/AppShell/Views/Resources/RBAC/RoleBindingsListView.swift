// Views/Resources/RBAC/RoleBindingsListView.swift — app_shell bounded context
// DDD role: View (Onda 2, RBAC category)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - RoleBindingsListViewModel

/// View model for the Kubernetes RoleBindings list view.
///
/// Loads `rbac.authorization.k8s.io/v1 RoleBinding` via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class RoleBindingsListViewModel {

    // MARK: State

    /// Lifecycle state of the role bindings list.
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

    private let logger = Logger(label: "k8smgr.app_shell.role_bindings_list")

    private static let gvk = GroupVersionKind(
        group: "rbac.authorization.k8s.io", version: "v1", kind: "RoleBinding"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads role bindings for the given cluster and namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    /// Re-fetches role bindings with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("rolebindings reload cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        do {
            let items = try await listPort.list(
                gvk: Self.gvk, namespace: namespace, clusterId: clusterId
            )
            logger.info("rolebindings loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("rolebindings load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - RoleBindingsListView

/// Displays Kubernetes RoleBindings: Name / Namespace / Role Ref / Age.
@MainActor
public struct RoleBindingsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = RoleBindingsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Role Bindings",
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
                RoleBindingRow(item: item)
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

// MARK: - RoleBindingRow

private struct RoleBindingRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                HStack(spacing: 8) {
                    if let ns = item.namespace {
                        Text(ns).font(.caption).foregroundStyle(.secondary)
                    }
                    let roleRef = item.annotations["roleRef.name"] ?? "—"
                    Text(roleRef).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
