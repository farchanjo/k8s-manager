// Views/Resources/Storage/CSIDriversListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Storage category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - CSIDriversListViewModel

/// View model for the Kubernetes CSIDrivers list view.
///
/// Cluster-scoped. Loads `storage.k8s.io/v1 CSIDriver`.
@Observable
@MainActor
public final class CSIDriversListViewModel {

    // MARK: State

    /// Lifecycle state of the CSI drivers list.
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

    private let logger = Logger(label: "k8smgr.app_shell.csi_drivers_list")

    private static let gvk = GroupVersionKind(
        group: "storage.k8s.io", version: "v1", kind: "CSIDriver"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads CSI drivers for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches CSI drivers.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("csidrivers reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: Self.gvk, namespace: nil, clusterId: clusterId)
            logger.info("csidrivers loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("csidrivers load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - CSIDriversListView

/// Displays cluster-scoped Kubernetes CSIDrivers: Name / Mode / Storage Capacity / Age.
@MainActor
public struct CSIDriversListView: View {

    let clusterId: ClusterId

    @State private var viewModel = CSIDriversListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "CSI Drivers",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            content
        }
        .modifier(ExportMenuContainer(
            kind: "CSIDriver",
            rows: viewModel.filteredRows.map { item in
                ResourceListRow(values: [
                    item.name, item.status, ageLabel(item.ageSeconds),
                ])
            },
            isHidden: viewModel.filteredRows.isEmpty
        ))
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
                CSIDriverRow(item: item)
                    .contextMenu {
                        // CSIDriver is excluded from FAB but context menu is still valid.
                        let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                            kind: "CSIDriver", name: item.name, family: .storage
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
            title: "Failed to load CSIDrivers",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}

// MARK: - CSIDriverRow

private struct CSIDriverRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                let mode = item.annotations["volumeLifecycleModes"] ?? "Persistent"
                let cap = item.annotations["storageCapacity"] == "true" ? "capacity-aware" : ""
                Text([mode, cap].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
