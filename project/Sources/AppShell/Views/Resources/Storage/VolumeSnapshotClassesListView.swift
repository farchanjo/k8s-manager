// Views/Resources/Storage/VolumeSnapshotClassesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Storage category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - VolumeSnapshotClassesListViewModel

/// View model for the Kubernetes VolumeSnapshotClasses list view.
///
/// Cluster-scoped. Loads `snapshot.storage.k8s.io/v1 VolumeSnapshotClass`.
@Observable
@MainActor
public final class VolumeSnapshotClassesListViewModel {

    // MARK: State

    /// Lifecycle state of the volume snapshot classes list.
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

    private let logger = Logger(label: "k8smgr.app_shell.volume_snapshot_classes_list")

    private static let gvk = GroupVersionKind(
        group: "snapshot.storage.k8s.io", version: "v1", kind: "VolumeSnapshotClass"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads volume snapshot classes for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches volume snapshot classes.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("volumesnapshotclasses reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: Self.gvk, namespace: nil, clusterId: clusterId)
            logger.info("volumesnapshotclasses loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("volumesnapshotclasses load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - VolumeSnapshotClassesListView

/// Displays cluster-scoped Kubernetes VolumeSnapshotClasses: Name / Driver / Age.
@MainActor
public struct VolumeSnapshotClassesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = VolumeSnapshotClassesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Volume Snapshot Classes",
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
                    secondary: item.annotations["driver"] ?? item.annotations["deletionPolicy"]
                )
                .contextMenu {
                    let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                        kind: "VolumeSnapshotClass", name: item.name, family: .storage
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
            title: "Failed to load VolumeSnapshotClasses",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}
