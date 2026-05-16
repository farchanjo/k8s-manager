// Views/Resources/Storage/VolumeSnapshotsListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Storage category)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - VolumeSnapshotsListViewModel

/// View model for the Kubernetes VolumeSnapshots list view.
///
/// Loads `snapshot.storage.k8s.io/v1 VolumeSnapshot` via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class VolumeSnapshotsListViewModel {

    // MARK: State

    /// Lifecycle state of the volume snapshots list.
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

    private let logger = Logger(label: "k8smgr.app_shell.volume_snapshots_list")

    private static let gvk = GroupVersionKind(
        group: "snapshot.storage.k8s.io", version: "v1", kind: "VolumeSnapshot"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads volume snapshots for the given cluster and namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    /// Re-fetches volume snapshots with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("volumesnapshots reload cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        do {
            let items = try await listPort.list(
                gvk: Self.gvk, namespace: namespace, clusterId: clusterId
            )
            logger.info("volumesnapshots loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("volumesnapshots load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - VolumeSnapshotsListView

/// Displays Kubernetes VolumeSnapshots: Name / Namespace / Source PVC / Status / Age.
@MainActor
public struct VolumeSnapshotsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = VolumeSnapshotsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Volume Snapshots",
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
                VolumeSnapshotRow(item: item)
            }
            .listStyle(.inset)
        }
    }

    private func errorView(_ error: Error) -> some View {
        ErrorStateView(
            title: "Failed to load VolumeSnapshots",
            error: error,
            retryable: true,
            onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
        )
    }
}

// MARK: - VolumeSnapshotRow

private struct VolumeSnapshotRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                HStack(spacing: 8) {
                    if let ns = item.namespace { Text(ns).font(.caption).foregroundStyle(.secondary) }
                    let src = item.annotations["volumeSnapshot.sourcePVC"] ?? "—"
                    Text("pvc: \(src)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            StatusChip(
                variant: StatusChipSemantic.chipVariant(forRawStatus: item.status),
                label: item.status
            )
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
