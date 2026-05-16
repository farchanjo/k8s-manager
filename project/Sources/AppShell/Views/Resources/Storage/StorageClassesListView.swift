// Views/Resources/Storage/StorageClassesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Storage category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - StorageClassesListViewModel

/// View model for the Kubernetes StorageClasses list view.
///
/// Cluster-scoped. Loads `storage.k8s.io/v1 StorageClass`.
@Observable
@MainActor
public final class StorageClassesListViewModel {

    // MARK: State

    /// Lifecycle state of the storage classes list.
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

    private let logger = Logger(label: "k8smgr.app_shell.storage_classes_list")

    private static let gvk = GroupVersionKind(
        group: "storage.k8s.io", version: "v1", kind: "StorageClass"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads storage classes for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches storage classes.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("storageclasses reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: Self.gvk, namespace: nil, clusterId: clusterId)
            logger.info("storageclasses loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("storageclasses load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - StorageClassesListView

/// Displays cluster-scoped Kubernetes StorageClasses: Name / Provisioner / Binding Mode / Age.
@MainActor
public struct StorageClassesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = StorageClassesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Storage Classes",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            content
        }
        .modifier(ExportMenuContainer(
            kind: "StorageClass",
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
                StorageClassRow(item: item)
                    .contextMenu {
                        let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                            kind: "StorageClass", name: item.name, family: .storage
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
            title: "Failed to load StorageClasses",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}

// MARK: - StorageClassRow

private struct StorageClassRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name).font(.body.monospaced())
                    if item.annotations["storageclass.kubernetes.io/is-default-class"] == "true" {
                        Text("default")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                let provisioner = item.labels["provisioner"] ?? "—"
                Text(provisioner).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
