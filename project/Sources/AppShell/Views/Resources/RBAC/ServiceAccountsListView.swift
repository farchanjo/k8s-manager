// Views/Resources/RBAC/ServiceAccountsListView.swift — app_shell bounded context
// DDD role: View (Onda 2, RBAC category)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - ServiceAccountsListViewModel

/// View model for the Kubernetes ServiceAccounts list view.
///
/// Loads core/v1 ServiceAccount via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class ServiceAccountsListViewModel {

    // MARK: State

    /// Lifecycle state of the service accounts list.
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

    private let logger = Logger(label: "k8smgr.app_shell.service_accounts_list")

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads service accounts for the given cluster and namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    /// Re-fetches service accounts with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("serviceaccounts reload cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        let gvk = GroupVersionKind.core("ServiceAccount")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            logger.info("serviceaccounts loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("serviceaccounts load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - ServiceAccountsListView

/// Displays Kubernetes ServiceAccounts: Name / Namespace / Secrets count / Age.
@MainActor
public struct ServiceAccountsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = ServiceAccountsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Service Accounts",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            namespace: $viewModel.namespace,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            content
        }
        .modifier(ExportMenuContainer(
            kind: "ServiceAccount",
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
                ServiceAccountRow(item: item)
                    .contextMenu {
                        let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                            kind: "ServiceAccount", name: item.name,
                            namespace: item.namespace, family: .accessControl
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
            title: "Failed to load ServiceAccounts",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}

// MARK: - ServiceAccountRow

private struct ServiceAccountRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                if let ns = item.namespace {
                    Text(ns).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
