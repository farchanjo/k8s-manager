// Views/Resources/Network/ServicesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Network category)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - ServicesListViewModel

/// View model for the Kubernetes Services list view.
///
/// Loads services via `KubernetesResourceListPort` for a given cluster and
/// optional namespace. Port-forward context menu action is surfaced per row.
@Observable
@MainActor
public final class ServicesListViewModel {

    // MARK: State

    /// Lifecycle state of the services list.
    public var loadState: AsyncResource<[ResourceListItem]> = .idle

    /// Active namespace filter. `nil` means all namespaces.
    public var namespace: String?

    /// Free-text search applied client-side over name and namespace.
    public var searchText: String = ""

    /// Currently selected row for context menus.
    public var selectedId: String?

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

    private let logger = Logger(label: "k8smgr.app_shell.services_list")

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads services for the given cluster and namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    /// Records a port-forward intent for the service with the given UID (Onda 3).
    public func portForwardRequested(uid: String) {
        guard let item = loadState.value?.first(where: { $0.uid == uid }) else { return }
        logger.info("port-forward requested for service=\(item.name)")
    }

    /// Re-fetches services with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("services reload cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        let gvk = GroupVersionKind.core("Service")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            logger.info("services loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("services load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - ServicesListView

/// Displays Kubernetes Services: Name / Namespace / Status / Age.
///
/// Context menu exposes "Port Forward" for rows, forwarding to a `.portForward` tab.
@MainActor
public struct ServicesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = ServicesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Services",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            namespace: $viewModel.namespace,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            servicesContent
        }
        .task { await viewModel.start(clusterId: clusterId, namespace: nil) }
    }

    // MARK: Private views

    @ViewBuilder
    private var servicesContent: some View {
        switch viewModel.loadState {
        case .idle, .loading where viewModel.filteredRows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            errorView(error)
        default:
            servicesList
        }
    }

    private var servicesList: some View {
        List(viewModel.filteredRows, id: \.uid) { item in
            ServiceRow(item: item)
                .contextMenu {
                    let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                        kind: "Service", name: item.name,
                        namespace: item.namespace, family: .network
                    ))
                    ForEach(actions) { action in
                        if action.id == "delete" {
                            Divider()
                            Button("Delete\u{2026}", role: .destructive) {}
                        } else if action.id == "port-forward" {
                            Button("Port Forward") {
                                viewModel.portForwardRequested(uid: item.uid)
                            }
                        } else {
                            Button(action.label) {}
                        }
                    }
                }
        }
        .listStyle(.inset)
    }

    private func errorView(_ error: Error) -> some View {
        ErrorStateView(
            title: "Failed to load Services",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}

// MARK: - ServiceRow

private struct ServiceRow: View {
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
            StatusBadge(raw: item.status)
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

